library(sf)
library(tidyverse)
library(stplanr)
library(tmap)
tmap_mode("view") # interactive maps
# piggyback::pb_download() # download data files
# remotes::install_github("atumworld/odrust")
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

# set.seed(42)
# od_jittered = odrust::odr_jitter(
#   od = viagens_zl, zones = zonas_od_to_jitter, subpoints = osm_sp,
#   disaggregation_threshold = 500, min_distance_meters = 100) # todo: try different thresholds
# plot(od_jittered$geometry, lwd = 0.1)

# piggyback::pb_download("od_jittered_ZL.gpkg")
od_jittered = st_read("./od_jittered_ZL.gpkg")

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
            `Percent bike` = bike / all,
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


sp_pct =  stats::glm(formula = `Percent bike` ~
                     rf_dist_km + sqrt(rf_dist_km) + I(rf_dist_km^2) + rf_avslope_perc +
                       rf_dist_km*rf_avslope_perc + sqrt(rf_dist_km) * rf_avslope_perc,
                     family = "quasibinomial",
                     data = routes_fast_base,
                     weights = all)

# residuals here are a different thing because of the model (count)
routes_fast_base$resids = routes_fast_base$`Percent bike` - sp_pct$fitted.values


sp_pct_foot =  stats::glm(formula = `Percent walk` ~
                       rf_dist_km + sqrt(rf_dist_km) + I(rf_dist_km^2) + rf_avslope_perc +
                       rf_dist_km*rf_avslope_perc + sqrt(rf_dist_km) * rf_avslope_perc,
                     family = "quasibinomial",
                     data = routes_fast_base,
                     weights = all)

routes_fast_base$resids_foot = routes_fast_base$`Percent walk` - sp_pct_foot$fitted.values

ggplot(routes_fast_base) +
  geom_density(aes(`Percent bike`), linetype="dashed") +
  geom_density(aes(sp_pct$fitted.values)) +
  xlim(0, 0.1) +
  theme_bw()

routes_fast_base_high_bike = routes_fast_base %>%
  ungroup() %>%
  slice_max(resids, n = 4000)  # a lot of zeros in bike trips, size has to be smaller than walk

routes_fast_base_high_foot = routes_fast_base %>%
  ungroup() %>%
  slice_max(resids_foot, n = 4000)


atum_bike = stats::glm(formula = `Percent bike` ~
                         rf_dist_km + sqrt(rf_dist_km) + I(rf_dist_km^2) + rf_avslope_perc +
                         rf_dist_km*rf_avslope_perc + sqrt(rf_dist_km) * rf_avslope_perc,
                       family = "quasibinomial",
                       data = routes_fast_base_high_bike,
                       weights = all)

atum_foot = stats::glm(formula = `Percent walk` ~
                         rf_dist_km + sqrt(rf_dist_km) + I(rf_dist_km^2) + rf_avslope_perc +
                         rf_dist_km*rf_avslope_perc + sqrt(rf_dist_km) * rf_avslope_perc,
                       family = "quasibinomial",
                       data = routes_fast_base_high_foot %>% filter(rf_dist_km < 6),
                       weights = all)


routes_fast_active = routes_fast_base %>%
  modelr::add_predictions(atum_foot, "logit_foot") %>%
  modelr::add_predictions(atum_bike, "logit_pcycle") %>%
  mutate(
    bike_increase_proportion = boot::inv.logit(logit_pcycle),
    foot_increase_proportion = boot::inv.logit(logit_foot),
    foot_increase_proportion = case_when(foot_increase_proportion < foot / all ~ foot / all,
                                         rf_dist_km > 6 ~ 0,
                                         TRUE ~ foot_increase_proportion),
    bike_increase_proportion = case_when(
      rf_dist_km > 30 ~ 0,
      TRUE ~ bike_increase_proportion
    ),
    foot_corto_prazo = all * foot_increase_proportion,
    car_reduction = case_when(
      foot_corto_prazo - foot >= car ~ car,
      foot_corto_prazo == 0 ~ 0,
      TRUE ~ car - (foot_corto_prazo - foot)
    ),
    car = car - car_reduction,
    foot = foot + car_reduction,
    car_reduction = case_when(                    # just to avoid some floating point problems
      car * bike_increase_proportion > car ~ car,
      TRUE ~ car * bike_increase_proportion
    ),
    car = car - car_reduction,
    bike = bike + car_reduction,
    `Percent walk` = foot / all
  )


routes_fast_go_dutch = routes_fast_base %>%
  mutate(
    bike_increase_proportion = uptake_pct_godutch_2020(
      distance = rf_dist_km,
      gradient = rf_avslope_perc
    ),
    car_reduction = car * bike_increase_proportion,
    car = car - car_reduction,
    bike = bike + car_reduction,
    `Percent walk` = foot / all
  )

routes_fast_ebikes = routes_fast_base %>%
  mutate(
    bike_increase_proportion = uptake_pct_ebike_2020(
      distance = rf_dist_km,
      gradient = rf_avslope_perc
    ),
    car_reduction = car * bike_increase_proportion,
    car = car - car_reduction,
    bike = bike + car_reduction,
    `Percent walk` = foot / all
  )


col_modes = c("#fe5f55", "grey", "#ffd166", "#90be6d", "#457b9d")

# Plot bar chart showing modal share by distance band for existing journeys
base_results = routes_fast_base %>%
  dplyr::select(dist_bands, car, other, public, bike, foot) %>%
  tidyr::pivot_longer(cols = matches("car|other|publ|bike|foot"), names_to = "mode") %>%
  mutate(mode = factor(mode, levels = c("car", "other", "public", "bike", "foot"), ordered = TRUE)) %>%
  group_by(dist_bands, mode) %>%
  summarise(Trips = sum(value))

active_results = routes_fast_active %>%
  dplyr::select(dist_bands, car, other, public, bike, foot) %>%
  tidyr::pivot_longer(cols = matches("car|other|publ|bike|foot"), names_to = "mode") %>%
  mutate(mode = factor(mode, levels = c("car", "other", "public", "bike", "foot"), ordered = TRUE)) %>%
  group_by(dist_bands, mode) %>%
  summarise(Trips = sum(value))

go_dutch_results = routes_fast_go_dutch %>%
  dplyr::select(dist_bands, car, other, public, bike, foot) %>%
  tidyr::pivot_longer(cols = matches("car|other|publ|bike|foot"), names_to = "mode") %>%
  mutate(mode = factor(mode, levels = c("car", "other", "public", "bike", "foot"), ordered = TRUE)) %>%
  group_by(dist_bands, mode) %>%
  summarise(Trips = sum(value))

ebikes_results = routes_fast_ebikes %>%
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

g2 = ggplot(active_results) +
  geom_col(aes(dist_bands, Trips, fill = mode)) +
  ggtitle("Cenário de Curto-Prazo") +
  xlab("Distância (km)") +
  scale_y_continuous(name = "Milhares de viagens / dia",
                     labels=function(x) format(x/1000,
                                               big.mark = ",",
                                               decimal.mark = ".",
                                               scientific = FALSE)) +
  scale_fill_manual(values = col_modes, name = "Modo") +
  theme_bw()

g3 = ggplot(go_dutch_results) +
  geom_col(aes(dist_bands, Trips, fill = mode)) +
  ggtitle("Cenário Go Dutch") +
  xlab("Distância (km)") +
  scale_y_continuous(name = "Milhares de viagens / dia",
                     labels=function(x) format(x/1000,
                                               big.mark = ",",
                                               decimal.mark = ".",
                                               scientific = FALSE)) +
  scale_fill_manual(values = col_modes, name = "Modo") +
  theme_bw()

g4 = ggplot(ebikes_results) +
  geom_col(aes(dist_bands, Trips, fill = mode)) +
  ggtitle("Cenário Ebike") +
  xlab("Distância (km)") +
  scale_y_continuous(name = "Milhares de viagens / dia",
                     labels=function(x) format(x/1000,
                                               big.mark = ",",
                                               decimal.mark = ".",
                                               scientific = FALSE)) +
  scale_fill_manual(values = col_modes, name = "Modo") +
  theme_bw()

(g1 | g2 ) / (g3 | g4 )


# Visualizations at the route level --------------------------------------------

rm("od_jittered", "osm_sp", "viagens_zl", "viagens_top", "viagens_top_sf")
gc()

sao_miguel = st_read("./sao_miguel_paulista.geojson")

base_bike = overline(routes_fast, "bike")
base_walk = overline(routes_fast, "foot")

active = routes_fast %>%
  select(zona_o, zona_d, route_number) %>%
  left_join(routes_fast_active, by=c("zona_o", "zona_d", "route_number"))

go_dutch = routes_fast %>%
  select(zona_o, zona_d, route_number) %>%
  left_join(routes_fast_go_dutch, by = c("zona_o", "zona_d", "route_number"))

ebikes = routes_fast %>%
  select(zona_o, zona_d, route_number) %>%
  left_join(routes_fast_ebikes, by = c("zona_o", "zona_d", "route_number"))

active_bike = overline(active, "bike")
ebikes_bike = overline(ebikes, "bike")
go_dutch_bike = overline(go_dutch, "bike")

active_walk = overline(active, "foot")

rm("ebikes", "go_dutch", "active")


tmap_mode("plot")

bike_brks = c(0, 100, 500, 1000, 5000, 10000, 20000)       # keep consistent with the active scenario
foot_brks = c(0, 1000, 5000, 10000, 25000, 50000)

bike1 = base_bike %>%
  tm_shape() +
  tm_lines("bike",
           title.col = "Viagens de bicicleta",
           palette = "-viridis",
           breaks = bike_brks) +
  tm_shape(sp_boundary) +
  tm_borders(col = "red") +
  tm_shape(sao_miguel) +
  tm_borders(col = "red", lty = "dashed") +
  tm_layout(
    title = "Base",
    legend.show = FALSE,
    frame = FALSE
  )

bike2 = active_bike %>%
  tm_shape() +
  tm_lines("bike",
           title.col = "Viagens de bicicleta",
           palette = "-viridis",
           breaks = bike_brks) +
  tm_shape(sp_boundary) +
  tm_borders(col = "red") +
  tm_shape(sao_miguel) +
  tm_borders(col = "red", lty = "dashed") +
  tm_layout(
    title = "Curto-Prazo",
    legend.show = FALSE,
    frame = FALSE
  )

bike3 = go_dutch_bike %>%
  tm_shape() +
  tm_lines("bike",
           title.col = "Viagens de bicicleta",
           palette = "-viridis",
           breaks = bike_brks) +
  tm_shape(sp_boundary) +
  tm_borders(col = "red") +
  tm_shape(sao_miguel) +
  tm_borders(col = "red", lty = "dashed") +
  tm_layout(
    title = "Go Dutch",
    legend.show = FALSE,
    frame = FALSE
  )

bike4 = ebikes_bike %>%
  tm_shape() +
  tm_lines("bike",
           title.col = "Viagens de bicicleta",
           palette = "-viridis",
           breaks = bike_brks) +
  tm_shape(sp_boundary) +
  tm_borders(col = "red") +
  tm_shape(sao_miguel) +
  tm_borders(col = "red", lty = "dashed") +
  tm_layout(
    title = "Ebikes",
    legend.show = FALSE,
    frame = FALSE
  )

tmap_arrange(bike1, bike2, bike3, bike4, ncol = 2) %>%
  tmap_save("route_level.png")

# Foot trips

foot1 = base_walk %>%
  tm_shape() +
  tm_lines("foot", palette = "-viridis", breaks = foot_brks) +
  tm_shape(sp_boundary) +
  tm_borders(col="red") +
  tm_shape(sao_miguel) +
  tm_borders(col = "red", lty = "dashed") +
  tm_layout(
    title = "Base",
    legend.show = FALSE,
    frame = FALSE
  )


foot2 = active_walk %>%
  tm_shape() +
  tm_lines("foot", palette = "-viridis", breaks = foot_brks) +
  tm_shape(sp_boundary) +
  tm_borders(col="red") +
  tm_shape(sao_miguel) +
  tm_borders(col = "red", lty = "dashed") +
  tm_layout(
    title = "Curto-Prazo",
    legend.show = FALSE,
    frame = FALSE
  )

tmap_arrange(foot1, foot2, ncol = 2) %>%
  tmap_save("route_level_foot.png")


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
              alpha = .5,
              title = "Aumento viagens de bicicleta") +
  tm_shape(sp_boundary) +
  tm_borders(col = "red")

tm_shape(zone_level) +
  tm_polygons(col = "delta_foot",
              alpha = .5,
              title = "Aumento de viagens a pé") +
  tm_shape(sp_boundary) +
  tm_borders(col = "red")
