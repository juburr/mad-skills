# Select imagery and test fixtures

Use small deterministic fixtures for correctness. A synthetic raster can
have a distinct value at each corner, an internal invalid region,
a valid zero, and a known CRS and affine transform. Add a licensed
production-format sample when testing codec, sensor metadata, cloud
masking, or deployed reader behavior. Record the source revision
or checksum and any redistribution requirements.

| Need | Starting point |
|---|---|
| Basemap demonstration or map-client smoke test | Natural Earth provides cartographic rasters at published map scales. [Raster downloads](https://www.naturalearthdata.com/downloads/50m-raster-data/), [terms of use](https://www.naturalearthdata.com/about/terms-of-use/) |
| Multispectral Earth observation | Choose the specific Sentinel-2 or Landsat product and processing level. Check per-band resolution, QA, and scaling. [Copernicus Sentinel-2](https://dataspace.copernicus.eu/data-collections/copernicus-sentinel-data/sentinel-2), [USGS Landsat Collection 2 Level-2](https://www.usgs.gov/landsat-missions/landsat-collection-2-level-2-science-products) |
| U.S. aerial orthophotography | Check the NAIP vintage, acquisition extent, bands, and metadata for the area. [USDA NAIP program](https://www.fsa.usda.gov/sites/default/files/documents/naip_infosheet_2017.pdf) |
| Public imagery tile service | NASA GIBS publishes visualization layers. Choose a layer, tile matrix, and time from the actual service capabilities. [NASA GIBS](https://www.earthdata.nasa.gov/data/tools/gibs) |

For analysis, start from the sensor product and its documentation.
Confirm acquisition time, processing level, sample units, scale and offset,
quality masks, and georeferencing. For a catalog, verify footprint
and acquisition metadata then resolve the intended asset. Check
attribution, caching, and redistribution terms for that specific asset
or service before bundling fixtures or mirroring tiles.
