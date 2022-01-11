library(sf)
library(tidyverse)
library(stplanr)

piggyback::pb_download()

OD_2017_v1 = readRDS("./OD_2017_v1.Rds")
centro_expandido = st_read("./centro_expandido.geojson")
zonas_od = readRDS("./zonas_od.Rds")

zonas_od_centro = zonas_od %>%          # sf_use_s2(FALSE)
  st_centroid() %>%
  st_transform(crs = "WGS84") %>%
  mutate(dentro_centro = st_within(.,
                                   centro_expandido,
                                   sparse=FALSE)
  ) %>%
  filter(dentro_centro == TRUE)

viagens_centro = OD_2017_v1 %>%
  select(zona_o, zona_d, modoprin, fe_via) %>%
  filter(
    (!is.na(modoprin)) &
    (zona_o %in% unique(zonas_od_centro$NumeroZona)) &
    (zona_d %in% unique(zonas_od_centro$NumeroZona))
    ) %>%
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
  rename(geo_code1 = zona_o,
         geo_code2 = zona_d) %>%
  mutate(geo_code1 = as.character(geo_code1),
         geo_code2 = as.character(geo_code2)
         )

zonas_od_centro = zonas_od %>%
  filter(NumeroZona %in% unique(zonas_od_centro$NumeroZona)) %>%
  st_transform("WGS84") %>%
  rename(InterZone = NumeroZona) %>%
  mutate(InterZone = as.character(InterZone))

write_csv(viagens_centro, "./od_sp_center.csv")
st_write(zonas_od_centro, "./zones_sp_center.geojson", append = FALSE)

system("odjitter --od-csv-path ./od_sp_center.csv --zones-path ./zones_sp_center.geojson --max-per-od 50000 --output-path result.geojson
")

od_jittered = sf::read_sf("result.geojson")
routes_fast = route(l = od_jittered, route_fun = cyclestreets::journey)
