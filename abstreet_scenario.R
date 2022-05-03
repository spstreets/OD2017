library(abstr)
library(sf)
library(tidyverse)
library(stplanr)

OD_2017_v1 = readRDS("./OD_2017_v1.Rds")
zonas_od = readRDS("./zonas_od.Rds")

set.seed(2022)

area_traffic_calming = st_read("area_traffic_calming.gpkg") %>%
  st_buffer(units::set_units(500, m))

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

od_sao_miguel_exp = OD_2017_v1 %>%
  select(zona_o, zona_d, fe_via, modoprin, h_saida, min_saida) %>%
  filter( (zona_o %in% unique(zonas_od_area$NumeroZona) | zona_d %in% (unique(zonas_od_area$NumeroZona))) & !is.na(modoprin)) %>%
  mutate(
    mode_ab_streets = case_when(
      modoprin %in% 1:6 ~ "Transit",
      modoprin == 16 ~ "Walk",
      modoprin == 9 | modoprin == 10 ~ "Drive",
      modoprin %in% c(7, 8, 11, 12, 13, 14, 17) ~ "other",
      modoprin == 15 ~ "Bike"
    ),
    departure = (h_saida + min_saida/60)*60^2,      # in seconds, for A/B Street
    trips = round(fe_via)
  ) %>%
  uncount(trips) %>%
  select(-fe_via, -modoprin, -h_saida, -min_saida)

od_sao_miguel_exp$departure = od_sao_miguel_exp$departure + rnorm(nrow(od_sao_miguel_exp),
                                                                  mean = 0,
                                                                  sd = 1200)    #  half hour

od_sao_miguel_exp$all = 1                   # I need this (fake) column to use odjitter

write_csv(od_sao_miguel_exp, "./od_sao_miguel.csv")

st_write(zonas_od %>% mutate(NumeroZona = as.character(NumeroZona)) %>% st_transform(crs = 4326),
         "zonas_od.geojson",
         append=FALSE)

jitter_query = paste0("odjitter jitter ",
                      "--od-csv-path ./od_sao_miguel.csv ",
                      "--origin-key zona_o ",
                      "--destination-key zona_d ",
                      "--zones-path ./zonas_od.geojson ",
                      "--zone-name-key NumeroZona ",
                      "--disaggregation-threshold 50000 ",
                      "--output-path ./sao-miguel-jittered.geojson "
)

system(jitter_query)

sao_miguel_disaggregated = st_read("./sao-miguel-jittered.geojson") %>%
  filter(mode_ab_streets != "other")

scenario = ab_json(sao_miguel_disaggregated,
                   mode_column = "mode_ab_streets",
                   scenario_name = "Full")

ab_save(scenario, "all_trips_buffer500m.json")
st_write(area_traffic_calming, "sao_miguel_buffer500m.geojson")


