library(sf)
library(tidyverse)

piggyback::pb_download()

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
  filter((zona_o %in% unique(zonas_od_centro$NumeroZona)) &
         (zona_d %in% unique(zonas_od_centro$NumeroZona))
        )

saveRDS(viagens_centro, "./trips-simulation.Rds")
