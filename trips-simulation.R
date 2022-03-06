library(sf)
library(tidyverse)
library(stplanr)
library(tmap)
tmap_mode("view") # interactive maps
# piggyback::pb_download() # download data files
remotes::install_github("atumworld/odrust")
# remotes::install_github("dabreegster/odjitter", subdir = "R")
library(pct)
library(patchwork)
sf::sf_use_s2(FALSE)

# piggyback::pb_download("./SIRGAS_GPKG_subprefeitura.gpkg")

# Read-in data ------------------------------------------------------------
OD_2017_v1 = readRDS("./OD_2017_v1.Rds")
zonas_od = readRDS("./zonas_od.Rds")
sp_boundary = st_read("./SIRGAS_GPKG_subprefeitura.gpkg") %>%
  sf::st_buffer(1) %>%
  sf::st_simplify() %>%
  sf::st_union() %>%
  sf::st_transform(4326)
# Download Brazil's road network, ~6m rows
# osm_network = osmextract::oe_get_network(place = "brazil", mode = "driving")
# Import with spatial filter (not tested)
# osm_network = osmextract::oe_get_network(place = "brazil", mode = "driving", boundary = sp_boundary)
# osm_sp = osm_network[st_transform(zonas_od, 4326), ] # solved with sp_boundary
# saveRDS(osm_sp, "osm_sp.Rds")
# piggyback::pb_upload("osm_sp.Rds")
osm_sp = readRDS("osm_sp.Rds")

sf::sf_use_s2(TRUE)
zona_leste = st_read("./SIRGAS_GPKG_subprefeitura.gpkg") %>%
  st_transform(crs = 4326) %>%
  filter(sp_nome %in% c("PENHA", "ERMELINO MATARAZZO", "SAO MIGUEL", "ITAIM PAULISTA",
                        "GUAIANASES", "ITAQUERA", "CIDADE TIRADENTES", "SAO MATEUS",
                        "ARICANDUVA-FORMOSA-CARRAO", "MOOCA", "SAPOPEMBA", "IPIRANGA",
                        "VILA PRUDENTE")
         ) %>%
  st_buffer(1) %>%
  st_simplify() %>%
  st_union()

# How do I add legends here??
tmap_mode("plot")
tm_shape(zonas_od) +
  tm_borders(col = "grey", alpha = .5) +
  tm_shape(sp_boundary) +
  tm_borders(col = "black") +
  tm_shape(zona_leste) +
  tm_fill(col="red", alpha=.5, title = "Zona Leste") +
  tm_layout(frame = FALSE)

tmap_mode("view")

zonas_od_leste = zonas_od %>%
  st_centroid() %>%
  st_transform(4326) %>%
  st_filter(y = zona_leste, .predicate = st_covered_by)


viagens_zl = OD_2017_v1 %>%
  filter(
    (!is.na(modoprin)) &
      (zona_o %in% zonas_od_leste$NumeroZona) &
      (zona_d %in% zonas_od_leste$NumeroZona)
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

zonas_od_zl = zonas_od %>%
  filter(NumeroZona %in% zonas_od_leste$NumeroZona) %>%
  st_transform(4326) %>%
  mutate(InterZone = as.character(NumeroZona))
zonas_od_to_jitter = zonas_od_zl %>%
  mutate(NumeroZona = as.character(NumeroZona))

sf_use_s2(FALSE)
# Sanity check desire lines data
summary(viagens_zl$all)
viagens_top = viagens_zl %>%
  filter(all > 10000)
viagens_top_sf = od::od_to_sf(viagens_top, zonas_od_to_jitter)
qtm(viagens_top_sf)

set.seed(42)
od_jittered = odrust::odr_jitter(
  od = viagens_zl, zones = zonas_od_to_jitter, subpoints = osm_sp,
  disaggregation_threshold = 500, min_distance_meters = 100) # todo: try different thresholds
plot(od_jittered$geometry, lwd = 0.1)

od_jittered %>%
  top_n(1000, all) %>%
  qtm()

# routes_fast = route(l = od_jittered, route_fun = cyclestreets::journey)
#
# piggyback::pb_download("routes_zl.gpkg")
routes_fast = sf::read_sf("routes_zl.gpkg")
names(routes_fast)

routes_fast_base = routes_fast %>%
  group_by(zona_o, zona_d, route_number) %>%
  mutate(
    rf_dist_km = length / 1000,
    rf_avslope_perc = mean(gradient_smooth),
    dist_bands = cut(x = rf_dist_km,
                     breaks = c(0, 1, 3, 6, 10, 15, 20, 30, 60),
                     include.lowest = TRUE)
  ) %>%
  sf::st_drop_geometry() %>%
  summarise(all = first(all),
            car = first(car),
            bike = first(bike),
            foot = first(foot),
            `Percent walk` = foot / all,
            public = first(public),
            other = first(other),
            rf_dist_km = first(rf_dist_km),
            rf_avslope_perc = first(rf_avslope_perc),
            dist_bands = first(dist_bands)
            )

# sanity checks
nrow(routes_fast_base)
summary(routes_fast_base$zona_o == routes_fast_base$zona_d)
sum(routes_fast_base$foot) / sum(routes_fast_base$all)
g1 = routes_fast_base %>%
  ggplot(aes(rf_dist_km, `Percent walk`, size = all, alpha = 0.1)) +
  geom_point(show.legend = FALSE) +
  geom_smooth(method = lm, se = FALSE, show.legend = FALSE) +
  xlim(c(0, 5)) +
  xlab("Distância (km)") +
  ylab("% de viagens a pé") +
  ggtitle("Todas as rotas") +
  scale_y_continuous(labels = scales::percent) +
  theme_bw()
g1

m1 = lm(`Percent walk` ~ rf_dist_km, data = routes_fast_base)
resids = m1$residuals + 1

routes_fast_base_high_walk = routes_fast_base %>%
  ungroup() %>%
  sample_n(size = 4000, weight = resids)

m2 = lm(`Percent walk` ~ rf_dist_km, data = routes_fast_base_high_walk)
sum(routes_fast_base_high_walk$foot) / sum(routes_fast_base_high_walk$all)

g2 = routes_fast_base_high_walk %>%
  ggplot(aes(rf_dist_km, `Percent walk`, size = all, alpha = 0.1)) +
  geom_point(show.legend = FALSE) +
  geom_smooth(method = lm, se = FALSE, show.legend = FALSE) +
  # geom_smooth(method = lm, formula = y ~ splines::bs(x, 2), se = FALSE) +
  xlim(c(0, 5)) +
  xlab("Distância (km)") +
  ylab("% de viagens a pé") +
  ggtitle("Maior propensão a viajar a pé") +
  scale_y_continuous(labels = scales::percent) +
  theme_bw()

g1 + g2

routes_fast_active = routes_fast_base %>%
  mutate(
    # Simplistic 'actdev' way of calculating walking uptake
    # foot_increase_proportion = case_when(
    #   # specifies that 50% of car journeys <1km in length will be replaced with walking
    #   rf_dist_km < 1 ~ 0.5,
    #   # specifies that 10% of car journeys 1-2km in length will be replaced with walking
    #   rf_dist_km >= 1 & rf_dist_km < 2 ~ 0.1,
    #   TRUE ~ 0
    # ),
    lm_foot_proportion = m2$coefficients[[1]] + m2$coefficients[[2]] * rf_dist_km,
    foot_increase_proportion = case_when(lm_foot_proportion < foot / all ~ foot / all, TRUE ~ lm_foot_proportion),
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
    bike = bike + car_reduction,
    `Percent walk` = foot / all
  )

sum(routes_fast_active$foot) / sum(routes_fast_active$all)

g3 = routes_fast_active %>%
  ggplot(aes(rf_dist_km, `Percent walk`, size = all, alpha = 0.1)) +
  geom_point(show.legend = FALSE) +
  geom_smooth(method = lm, se = FALSE, show.legend = FALSE) +
  xlim(c(0, 5)) +
  xlab("Distância (km)") +
  ylab("% de viagens a pé") +
  ggtitle("Cenário contrafactual") +
  scale_y_continuous(labels = scales::percent) +
  theme_bw()

g1 + g2 + g3

col_modes = c("#fe5f55", "grey", "#ffd166", "#90be6d", "#457b9d")
# Plot bar chart showing modal share by distance band for existing journeys
base_results = routes_fast_base %>%
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
  dplyr::select(dist_bands, car, other, public, bike, foot) %>%
  tidyr::pivot_longer(cols = matches("car|other|publ|bike|foot"), names_to = "mode") %>%
  mutate(mode = factor(mode, levels = c("car", "other", "public", "bike", "foot"), ordered = TRUE)) %>%
  group_by(dist_bands, mode) %>%
  summarise(Trips = sum(value))

g2 = ggplot(active_results) +
  geom_col(aes(dist_bands, Trips, fill = mode)) +
  ggtitle("Cenário Contrafactual") +
  xlab("Distância (km)") +
  scale_y_continuous(name = "Milhares de viagens / dia",
                     labels=function(x) format(x/1000,
                                               big.mark = ",",
                                               decimal.mark = ".",
                                               scientific = FALSE)) +
  scale_fill_manual(values = col_modes, name = "Modo") +
  theme_bw()
g1 + g2


# Visualizations at the route level --------------------------------------------

base_bike = overline(routes_fast, "bike")
base_walk = overline(routes_fast, "foot")

sao_miguel = st_read("./sao_miguel_paulista.geojson")

scenario = routes_fast %>%
  select(zona_o, zona_d, route_number) %>%
  left_join(routes_fast_active, by=c("zona_o", "zona_d", "route_number"))

scenario_bike = overline(scenario, "bike")
scenario_walk = overline(scenario, "foot")

bike_brks = c(0, 100, 500, 1000, 5000, 10000, 20000)       # keep consistent with the active scenario
foot_brks = c(0, 1000, 5000, 10000, 25000, 50000)

base_bike %>%
  tm_shape() +
  tm_lines("bike", palette = "-viridis", breaks = bike_brks) +
  tm_shape(sp_boundary) +
  tm_borders(col = "red", alpha = 0.5) +
  tm_shape(sao_miguel) +
  tm_borders(col = "red", lty = "dashed")

scenario_bike %>%
  tm_shape() +
  tm_lines("bike", palette = "-viridis", breaks = bike_brks) +
  tm_shape(sp_boundary) +
  tm_borders(col="red", alpha = 0.5) +
  tm_shape(sao_miguel) +
  tm_borders(col = "red", lty = "dashed")

base_walk %>%
  tm_shape() +
  tm_lines("foot", palette = "-viridis", breaks = foot_brks) +
  tm_shape(sp_boundary) +
  tm_borders(col="red", alpha = 0.5) +
  tm_shape(sao_miguel) +
  tm_borders(col = "red", lty = "dashed")

scenario_walk %>%
  tm_shape() +
  tm_lines("foot", palette = "-viridis", breaks = foot_brks) +
  tm_shape(sp_boundary) +
  tm_borders(col="red", alpha = 0.5) +
  tm_shape(sao_miguel) +
  tm_borders(col = "red", lty = "dashed")


# Visualizations at the Zone level ---------------------------------------------

zone_level = routes_fast_base %>%
  ungroup() %>%
  select(zona_o, zona_d, route_number, bike, foot) %>%
  rename(foot_base = foot, bike_base = bike) %>%
  left_join(routes_fast_active, by=c("zona_o", "zona_d", "route_number")) %>%
  rename(bike_scenario = bike, foot_scenario = foot) %>%
  select(zona_o, bike_base, bike_scenario, foot_base, foot_scenario) %>%
  group_by(zona_o) %>%
  summarise_all(sum) %>%
  ungroup() %>%
  mutate(delta_bike = bike_scenario - bike_base,
         delta_foot = foot_scenario - foot_base,
         zona_o = as.numeric(zona_o)
         ) %>%
  left_join(zonas_od, by=c("zona_o"="NumeroZona")) %>%
  st_as_sf()

tm_shape(zone_level) +
  tm_polygons(col = "delta_bike",
              title = "Aumento viagens de bicicleta") +
  tm_shape(sp_boundary) +
  tm_borders(col = "red")

tm_shape(zone_level) +
  tm_polygons(col = "delta_foot",
              title = "Aumento de viagens a pé") +
  tm_shape(sp_boundary) +
  tm_borders(col = "red")










