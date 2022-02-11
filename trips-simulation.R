library(sf)
library(tidyverse)
library(stplanr)
library(tmap)
tmap_mode("view") # interactive maps
# piggyback::pb_download() # download data files
library(pct)
library(abstr)
library(patchwork)

OD_2017_v1 = readRDS("./OD_2017_v1.Rds")
zonas_od = readRDS("./zonas_od.Rds")

viagens_sp = OD_2017_v1 %>%
  filter(
    (!is.na(modoprin)) &
      (muni_o == 36) &
      (muni_d == 36)
  ) %>%
  select(zona_o, zona_d, modoprin, fe_via) %>%
  mutate(
    mode_ab_streets = case_when(
      modoprin %in% 1:6 ~ "public",
      modoprin == 16 ~ "foot",
      modoprin == 9 | modoprin == 10 ~ "car",
      modoprin %in% c(7, 8, 11, 12, 13, 14, 17) ~ "other",
      modoprin == 15 ~ "bike"
    )
  ) %>%
  group_by(zona_o, zona_d, mode_ab_streets) %>%
  summarise(trips = round(sum(fe_via))) %>%          # round to avoid decimals (sampling weights here...)
  ungroup() %>%
  pivot_wider(names_from = mode_ab_streets,
              values_from = trips) %>%
  replace(is.na(.), 0) %>%
  mutate(all = public + foot + car + other + bike) %>%
  mutate(geo_code1 = as.character(zona_o),
         geo_code2 = as.character(zona_d)
         )

zonas_od_sp = zonas_od %>%
  filter(NomeMunici == "São Paulo") %>%
  st_transform("WGS84") %>%
  mutate(InterZone = as.character(NumeroZona))

write_csv(viagens_sp, "./od_sp.csv")
st_write(zonas_od_sp, "./zones_sp.geojson", append = FALSE)

# old version of odjitter (?)
system("odjitter --od-csv-path ./od_sp.csv --zones-path ./zones_sp.geojson --max-per-od 500000 --output-path trips_sp_jittered.geojson")

# TODO: sample from the road network, e.g. with:
# system("odjitter --od-csv-path ./od_sp_center.csv --zones-path ./zones_sp_center.geojson --subpoints-path osm_network.geojson --max-per-od 50000 --output-path result.geojson")

od_jittered = sf::read_sf("trips_sp_jittered.geojson")
od_jittered %>%
  top_n(1000, all) %>%
  qtm()

# routes_fast = route(l = od_jittered, route_fun = cyclestreets::journey)
#
# # These routes failed: 1, 274, 424, 577, 609, 787, 943, 1197, 1285, 1349, 1385, 2025, 2092, 2230, 2336, 2356, 2369, 2371, 2485, 2490, 2571, 2811, 3009, 3281, 3285, 3314, 3436, 3446, 3639, 3683, 3809, 3977, 4032, 4063, 4111, 4672, 4723, 4727, 4729, 4835, 4842, 4872, 4920, 4937, 4965, 4966, 4975, 5059, 5167, 5234, 5589, 5595, 5629, 5651, 5754, 5841, 5914, 5976, 5978, 5983, 5984, 6022, 6247, 6328, 6497, 6499, 6518, 6818, 6925, 6938
# # The first of which was:
# #   <simpleError in stats::filter(x, rep(1/n, n), sides = 2): 'filter' is longer than time series>
# piggyback::pb_upload("routes_fast.geojson")
# piggyback::pb_download_url("routes_fast.geojson")
routes_fast = sf::read_sf("routes_sp_city.gpkg")
names(routes_fast)

# routes_car = route(l = od_jittered,
#                    route_fun = route_osrm,
#                    osrm.profile = "car")
# # These routes failed: 514, 2438, 5720, 6259
# # The first of which was:
# #  <simpleError in open.connection(con, "rb"): cannot open the connection to 'https://routing.openstreetmap.de/routed-car/route/v1/driving/-46.6348553708288,-23.5349495769585;-46.6259491874601,-23.5402833338891?alternatives=false&geometries=geojson&steps=false&overview=full'>
# write_sf(routes_car, "routes_car_center.geojson")
# piggyback::pb_upload("routes_car_center.geojson")
# piggyback::pb_download("routes_car_center.geojson")
# routes_car = sf::read_sf("routes_car_center.geojson")
# names(routes_car)

# After that: group the routes by unique origin and destination and calculate the scenarios, e.g.
# building on this:
#   https://github.com/ITSLeeds/pct/blob/1bc8b202b2fc9d1436b973bf97523777adca9523/data-raw/training-dec-2021.Rmd#L471

routes_fast_base = routes_fast %>%
  group_by(geo_code1, geo_code2) %>%
  mutate(
    rf_dist_km = length / 1000,
    rf_avslope_perc = mean(gradient_smooth),
    dist_bands = cut(x = rf_dist_km, breaks = c(0, 1, 3, 6, 10, 15, 20, 30, 60), include.lowest = TRUE)
  ) %>%
  summarise(geometry = st_union(geom),
            all = first(all),
            car = first(car),
            bike = first(bike),
            foot = first(foot),
            public = first(public),
            other = first(other),
            rf_dist_km = first(rf_dist_km),
            rf_avslope_perc = first(rf_avslope_perc),
            dist_bands = first(dist_bands)
            )

routes_fast_active = routes_fast_base %>%
  mutate(
    foot_increase_proportion = case_when(
      # specifies that 50% of car journeys <1km in length will be replaced with walking
      rf_dist_km < 1 ~ 0.5,
      # specifies that 10% of car journeys 1-2km in length will be replaced with walking
      rf_dist_km >= 1 & rf_dist_km < 2 ~ 0.1,
      TRUE ~ 0
    ),
    # Specify the Go Dutch scenario we will use to replace remaining car trips with cycling
    bike_increase_proportion = uptake_pct_godutch_2020(
      distance = rf_dist_km,
      gradient = rf_avslope_perc
    ),
    # Make the changes specified above
    car_reduction = car * foot_increase_proportion,
    car = car - car_reduction,
    foot = foot + car_reduction,
    car_reduction = car * bike_increase_proportion,
    car = car - car_reduction,
    bike = bike + car_reduction
  )

col_modes = c("#fe5f55", "grey", "#ffd166", "#90be6d", "#457b9d")
# Plot bar chart showing modal share by distance band for existing journeys
base_results = routes_fast_base %>%
  sf::st_drop_geometry() %>%
  dplyr::select(dist_bands, car, other, public, bike, foot) %>%
  tidyr::pivot_longer(cols = matches("car|other|publ|bike|foot"), names_to = "mode") %>%
  mutate(mode = factor(mode, levels = c("car", "other", "public", "bike", "foot"), ordered = TRUE)) %>%
  group_by(dist_bands, mode) %>%
  summarise(Trips = sum(value))

g1 = ggplot(base_results) +
  geom_col(aes(dist_bands, Trips, fill = mode)) +
  ggtitle("Cenário base") +
  xlab("Distância (km)") +
  scale_y_continuous(name = "Milhares de viagens / dia",
                     labels=function(x) format(x/1000,
                                               big.mark = ",",
                                               decimal.mark = ".",
                                               scientific = FALSE)) +
  scale_fill_manual(values = col_modes, name = "Modo") +
  theme_bw()
g1

active_results = routes_fast_active %>%
  sf::st_drop_geometry() %>%
  dplyr::select(dist_bands, car, other, public, bike, foot) %>%
  tidyr::pivot_longer(cols = matches("car|other|publ|bike|foot"), names_to = "mode") %>%
  mutate(mode = factor(mode, levels = c("car", "other", "public", "bike", "foot"), ordered = TRUE)) %>%
  group_by(dist_bands, mode) %>%
  summarise(Trips = sum(value))

g2 = ggplot(active_results) +
  geom_col(aes(dist_bands, Trips, fill = mode)) +
  ggtitle(expression(paste("Cenário ", italic("Go Active")))) +
  xlab("Distância (km)") +
  scale_y_continuous(name = "Milhares de viagens / dia",
                     labels=function(x) format(x/1000,
                                               big.mark = ",",
                                               decimal.mark = ".",
                                               scientific = FALSE)) +
  scale_fill_manual(values = col_modes, name = "Modo") +
  theme_bw()
g2

routes_fast_base$geo_type = st_geometry_type(routes_fast_base$geometry)

routes_fast_base1 = routes_fast_base %>%
  filter(geo_type == "MULTILINESTRING") %>%
  st_cast("LINESTRING")                       # repeats the multilinestrings in several single linestrings if the df has only multilnestrings

routes_fast_base2 = routes_fast_base %>%
  filter(geo_type == "LINESTRING")

routes_fast_base_fixed = rbind(routes_fast_base1, routes_fast_base2)

rnet_brks = c(0, 100, 500, 1000, 5000, 10000, 20000)       # keep consistent with the active scenario

rnet_base_cycle = overline(routes_fast_base_fixed, "bike")

sp_bounds = geobr::read_municipality(code_muni = 3550308) %>%
  st_transform(crs = 4326)

rnet_base_cycle %>%
  tm_shape() +
  tm_lines("bike", palette = "-viridis", breaks = rnet_brks) +
  tm_shape(sp_bounds) +
  tm_borders(col="red")


routes_fast_active$geo_type = st_geometry_type(routes_fast_active$geometry)

routes_fast_active1 = routes_fast_active %>%
  filter(geo_type == "MULTILINESTRING") %>%
  st_cast("LINESTRING")                       # repeats the multilinestrings in several single linestrings if the df has only multilnestrings

routes_fast_active2 = routes_fast_active %>%
  filter(geo_type == "LINESTRING")

routes_fast_active_fixed = rbind(routes_fast_active1, routes_fast_active2)

rnet_active_cycle = overline(routes_fast_active_fixed, "bike")

rnet_active_cycle %>%
  tm_shape() +
  tm_lines("bike", palette = "-viridis", breaks = rnet_brks) +
  tm_shape(sp_bounds) +
  tm_borders(col="red")


g1 + g2

# After that: group the routes by unique origin and destination and calculate the scenarios, e.g.
# building on this:
#   https://github.com/ITSLeeds/pct/blob/1bc8b202b2fc9d1436b973bf97523777adca9523/data-raw/training-dec-2021.Rmd#L471

# area_traffic_calming = st_read("/home/lucas/Downloads/areatargetfortrafficcalming/perimetro_sm.shp")
# st_write(area_traffic_calming, "area_traffic_calming.gpkg")
# piggyback::pb_upload("area_traffic_calming.gpkg")
# piggyback::pb_download("area_traffic_calming.gpkg")

area_traffic_calming = st_read("area_traffic_calming.gpkg")

zonas_od_area = zonas_od %>%          # sf_use_s2(FALSE)
  st_centroid() %>%
  st_transform(crs = "WGS84") %>%
  mutate(dentro_area = st_within(.,
                                   area_traffic_calming,
                                   sparse=FALSE)
  ) %>%
  filter(dentro_area == TRUE)

trips_inside_area = OD_2017_v1 %>%
  filter(zona_o %in% unique(zonas_od_area$NumeroZona) | zona_d %in% (unique(zonas_od_area$NumeroZona))) %>%
  od2line(., zonas_od) %>%
  od::od_jitter(., zonas_od) %>%
  st_transform(crs = "WGS84")

# car_routes_area = route(l = trips_inside_area,
#                         route_fun = route_osrm,
#                         osrm.profile = "car")

# st_write(car_routes_area, "car_routes_area_04-02-2022.gpkg")

# bike_routes_area = route(l = trips_inside_area,
#                         route_fun = cyclestreets::journey)

# st_write(bike_routes_area, "bike_routes_area_04-02-2022.gpkg")

# ------------------------------------------------------------------------------

OD_2017_v1 %>%
  select(zona_o, zona_d, modoprin, fe_via) %>%
  filter( (zona_o %in% unique(zonas_od_area$NumeroZona) | zona_d %in% (unique(zonas_od_area$NumeroZona))) & !is.na(modoprin)) %>%
  mutate(
    mode_ab_streets = case_when(
      modoprin %in% 1:6 ~ "public",
      modoprin == 16 ~ "foot",
      modoprin == 9 | modoprin == 10 ~ "car",
      modoprin %in% c(7, 8, 11, 12, 13, 14, 17) ~ "other",
      modoprin == 15 ~ "bike"
    )
  ) %>%
  group_by(zona_o, zona_d, mode_ab_streets) %>%
  summarise(trips = round(sum(fe_via))) %>%          # round to avoid decimals (sampling weights here...)
  ungroup() %>%
  pivot_wider(names_from = mode_ab_streets,
              values_from = trips) %>%
  replace(is.na(.), 0) %>%
  write_csv("./od_sao_miguel.csv")

st_write(zonas_od %>% mutate(NumeroZona = as.character(NumeroZona)) %>% st_transform(crs = 4326),
         "zonas_od.geojson",
         append=FALSE)

jitter_query = paste0("odjitter disaggregate ",
                      "--od-csv-path ./od_sao_miguel.csv ",
                      "--origin-key zona_o ",
                      "--destination-key zona_d ",
                      "--zones-path ./zonas_od.geojson ",
                      "--zone-name-key NumeroZona ",
                      "--output-path ./sao-miguel-disaggregated.geojson "
                      )

system(jitter_query)

sao_miguel_disaggregated_sample = st_read("./sao-miguel-disaggregated.geojson") %>%
  sample_n(10000) %>%
  st_write("scenario.geojson")
