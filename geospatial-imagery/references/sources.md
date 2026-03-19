# Imagery Sources and Acquisition Reference

This reference covers the full landscape of geospatial imagery sources: how imagery is captured, where to obtain it (free and commercial), defense/intelligence programs, imagery marketplaces, and data delivery mechanisms.

---

## Satellite and Aircraft Imaging Systems

### Optical Satellite Imaging

Optical satellites capture reflected sunlight in visible and near-infrared wavelengths, producing imagery similar to aerial photography. The sensor records radiance values across defined spectral bands. Resolution is determined by the sensor's ground sample distance (GSD) -- the area on the ground represented by a single pixel.

**Resolution classes:**

| Class | GSD | Example Sensors | Typical Use Cases |
|---|---|---|---|
| Sub-meter | < 1m | WorldView-3 (31cm), Pleiades Neo (30cm), SkySat (50cm) | Building identification, infrastructure mapping, damage assessment |
| High (1-5m) | 1-5m | PlanetScope (3.7m), SPOT 7 (1.5m), RapidEye (5m) | Agriculture monitoring, urban mapping, change detection |
| Medium (10-30m) | 10-30m | Sentinel-2 (10m), Landsat 8/9 (30m) | Regional land cover, vegetation health, water resources |
| Coarse (>100m) | 100m+ | MODIS (250-1000m), VIIRS (375-750m) | Global weather, ocean color, fire monitoring |

**Panchromatic vs. multispectral:** Most high-resolution satellites carry both a panchromatic sensor (single wide band, highest resolution) and a multispectral sensor (multiple narrower bands, lower resolution). Pan-sharpening fuses the two to produce high-resolution color imagery.

### Synthetic Aperture Radar (SAR)

SAR sensors emit microwave pulses and record the reflected signal (backscatter). Unlike optical sensors, SAR works through clouds, at night, and in any weather condition -- making it critical for persistent monitoring.

**How SAR works:**
1. The satellite transmits microwave pulses toward the ground
2. The radar antenna records the amplitude and phase of the return signal
3. The satellite's motion along its orbit creates a "synthetic" aperture much larger than the physical antenna
4. Signal processing combines returns from multiple positions to achieve fine resolution

**SAR data products:**
- **SLC (Single Look Complex)**: Preserves amplitude and phase; required for interferometry (InSAR)
- **GRD (Ground Range Detected)**: Amplitude only, projected to ground range; simpler to use
- **Polarimetric**: Dual-pol (VV+VH or HH+HV) or quad-pol (HH+HV+VV+VH) for surface classification

**SAR advantages:**
- All-weather, day/night acquisition
- Penetrates clouds, smoke, and some vegetation canopy
- Sensitive to surface roughness, moisture content, and structure
- Enables interferometry (InSAR) for millimeter-scale ground deformation measurement

**Key SAR satellites:**

| Satellite | Operator | Band | Resolution | Revisit |
|---|---|---|---|---|
| Sentinel-1 | ESA | C-band | 5m (IW mode) | 6-12 days |
| RADARSAT-2 | MDA | C-band | 1-100m | 24 days |
| TerraSAR-X / TanDEM-X | Airbus | X-band | 0.25-40m | 11 days |
| ALOS-2 PALSAR-2 | JAXA | L-band | 1-100m | 14 days |
| Capella Space | Capella | X-band | 0.3-0.5m | < 6 hours (constellation) |
| ICEYE | ICEYE | X-band | 0.25-15m | < 20 hours (constellation) |
| Umbra | Umbra | X-band | 0.16-1m | Hours (tasking) |

### Multispectral vs. Hyperspectral

| Characteristic | Multispectral | Hyperspectral |
|---|---|---|
| Band count | 4-13 bands | 100-300+ bands |
| Spectral range | Discrete broad bands (10-100nm wide) | Contiguous narrow bands (5-10nm wide) |
| Spatial resolution | Higher (limited bands = more photons per pixel) | Lower (many bands = fewer photons per pixel) |
| Data volume | Moderate | Very large |
| Use cases | Land cover classification, vegetation indices, water quality | Mineral identification, crop species discrimination, material detection |

**Common multispectral bands:**

| Band | Wavelength (approx.) | Purpose |
|---|---|---|
| Coastal/Aerosol | 0.43-0.45 um | Atmospheric correction, shallow water |
| Blue | 0.45-0.51 um | Water penetration, vegetation discrimination |
| Green | 0.53-0.59 um | Vegetation vigor, peak reflectance |
| Red | 0.64-0.67 um | Chlorophyll absorption, vegetation stress |
| Red Edge | 0.70-0.73 um | Vegetation health transition zone |
| NIR | 0.77-0.90 um | Vegetation biomass, water body delineation |
| SWIR-1 | 1.55-1.75 um | Soil moisture, mineral content, burn scars |
| SWIR-2 | 2.08-2.35 um | Geology, mineral mapping |
| Thermal | 10.6-12.5 um | Surface temperature, heat emission |

### Aerial Platforms

| Platform | Altitude | Resolution | Coverage Rate | Cost | Best For |
|---|---|---|---|---|---|
| Fixed-wing aircraft | 1,000-12,000m | 5-30cm | High (large areas) | High per-flight, low per-km2 | County/state-level mapping, NAIP |
| Helicopter | 300-3,000m | 2-15cm | Moderate | Very high | Corridor mapping, inspection |
| Fixed-wing UAV/drone | 60-400m | 1-5cm | Moderate | Low per-flight | Farm fields, construction sites |
| Multi-rotor drone | 10-120m | 0.5-3cm | Low (small areas) | Lowest per-flight | Site inspection, small area mapping |

**Tradeoffs:**
- Higher altitude = wider coverage per pass but lower resolution
- Aircraft can cover large areas efficiently; drones provide extreme resolution for small areas
- Manned aircraft require licensed pilots and airspace coordination; drones face altitude and line-of-sight restrictions (in the US, FAA Part 107)
- Weather constraints: optical aerial platforms are grounded by clouds, wind, and rain

### Key Satellite Constellations

| Satellite | Operator | Type | Resolution (Pan/MS) | Revisit | Bands | Launch |
|---|---|---|---|---|---|---|
| WorldView-3 | Maxar | Optical | 31cm / 1.24m | < 1 day | 8 MS + 8 SWIR + CAVIS | 2014 |
| WorldView Legion | Maxar | Optical | 30cm / 1.2m | Multiple/day | 8 MS + SWIR | 2024 |
| GeoEye-1 | Maxar | Optical | 41cm / 1.65m | < 3 days | 4 MS | 2008 |
| Pleiades Neo | Airbus | Optical | 30cm / 1.2m | Daily | 6 MS | 2021 |
| SPOT 7 | Airbus | Optical | 1.5m / 6m | 1-3 days | 4 MS | 2014 |
| PlanetScope | Planet | Optical | -- / 3.7m | Daily (global) | 8 MS | 2016+ |
| SkySat | Planet | Optical | 50cm / -- | Multiple/day | 4 MS + Pan + Video | 2013+ |
| Sentinel-2A/B | ESA | Optical | -- / 10-60m | 5 days | 13 MS | 2015/2017 |
| Landsat 8 | USGS/NASA | Optical | 15m / 30m | 16 days | 11 MS/TIR | 2013 |
| Landsat 9 | USGS/NASA | Optical | 15m / 30m | 16 days | 11 MS/TIR | 2021 |
| Sentinel-1A/C | ESA | SAR (C) | 5m (IW) | 6-12 days | Dual-pol | 2014/2024 |
| RADARSAT Constellation | CSA/MDA | SAR (C) | 1-100m | 4 days | Dual/compact pol | 2019 |
| BlackSky | BlackSky | Optical | ~1m | Frequent | MS | 2018+ |
| Jilin-1 | Chang Guang | Optical | 0.5-0.75m | Revisit varies | MS + Video | 2015+ |

---

## Free Imagery Sources

### Best Starter Dataset for Testing

**For someone who just wants to test a custom tile server immediately:**

**Natural Earth** is the recommended starting point. Download the medium-scale raster basemap (~260 MB), convert to COG, and start tiling in minutes:

```bash
# Download Natural Earth raster basemap (1:50m scale, ~260 MB)
curl -L -o NE1_50M_SR_W.zip \
  https://naciscdn.org/naturalearth/50m/raster/NE1_50M_SR_W.zip
unzip NE1_50M_SR_W.zip

# Convert to COG for efficient serving
gdal_translate -of COG -co COMPRESS=JPEG -co QUALITY=85 \
  NE1_50M_SR_W.tif natural_earth_cog.tif

# Generate tiles directly
gdal2tiles.py -z 0-6 -w leaflet natural_earth_cog.tif ./tiles/
```

This gives a complete world basemap suitable for zoom levels 0-6. For higher zoom testing with real satellite data, use the Sentinel-2 sample described below.

### Natural Earth

**What:** Free vector and raster map data at 1:10m, 1:50m, and 1:110m scales. Public domain. Maintained by volunteer cartographers.

**Resolution:** Not satellite imagery -- cartographic raster basemaps at global scales.

**Coverage:** Global.

**Formats:** GeoTIFF (raster), Shapefile (vector), GeoPackage (vector).

**Download:**

| Product | Scale | Size | URL |
|---|---|---|---|
| Cross-blended hypsometric tints | 1:10m | ~700 MB | `https://naciscdn.org/naturalearth/10m/raster/NE1_HR_LC_SR_W_DR.zip` |
| Natural Earth I (shaded relief + water) | 1:50m | ~260 MB | `https://naciscdn.org/naturalearth/50m/raster/NE1_50M_SR_W.zip` |
| Natural Earth II | 1:50m | ~175 MB | `https://naciscdn.org/naturalearth/50m/raster/NE2_50M_SR_W.zip` |
| Gray Earth (grayscale) | 1:50m | ~75 MB | `https://naciscdn.org/naturalearth/50m/raster/GRAY_50M_SR_W.zip` |
| Ocean bottom | 1:50m | ~85 MB | `https://naciscdn.org/naturalearth/50m/raster/OB_50M.zip` |

```bash
# Download all rasters at 50m scale
for f in NE1_50M_SR_W NE2_50M_SR_W GRAY_50M_SR_W; do
  curl -L -O "https://naciscdn.org/naturalearth/50m/raster/${f}.zip"
done
```

### USGS Earth Explorer

**What:** The USGS Earth Resources Observation and Science (EROS) Center's primary portal for searching and downloading satellite imagery, aerial photography, and elevation data. Hosts Landsat, NAIP, declassified satellite imagery, and more.

**Resolution:** Varies by dataset. Landsat: 30m multispectral, 15m pan. NAIP: ~1m.

**Coverage:** Landsat: global. NAIP: contiguous US.

**Formats:** GeoTIFF (Landsat Collection 2), MrSID and JPEG2000 (NAIP).

**How to access:**

1. Create a free account at `https://earthexplorer.usgs.gov/`
2. Use the web interface to define area of interest, date range, and cloud cover
3. Search datasets (Landsat Collection 2, NAIP, etc.)
4. Download individual scenes or use bulk download

**Programmatic access via USGS Machine-to-Machine (M2M) API:**

```bash
# Install usgs CLI tool (Python)
pip install usgs

# Login
usgs login --username YOUR_USERNAME --password YOUR_PASSWORD

# Search Landsat 8 Collection 2 Level 2
usgs search --node EE --dataset "landsat_ot_c2_l2" \
  --bbox "-105.5 39.5 -104.5 40.5" \
  --start-date "2023-06-01" --end-date "2023-08-31" \
  --max-cloud-cover 20
```

**Landsat data is also available on AWS and Google Cloud -- see AWS Open Data section below.**

### Copernicus Data Space Ecosystem

**What:** The European Space Agency (ESA) provides free access to Sentinel satellite data. The Copernicus Data Space Ecosystem replaced the older Copernicus Open Access Hub (SciHub) as the primary access point.

**Key datasets:**
- **Sentinel-1**: SAR (C-band), 5m IW mode, dual-pol (VV+VH), 6-12 day revisit
- **Sentinel-2**: Multispectral, 10-60m, 13 bands, 5-day revisit
- **Sentinel-3**: Ocean/land monitoring, 300m-1km
- **Sentinel-5P**: Atmospheric composition

**Formats:** Sentinel-2: JPEG2000 (original SAFE format) or COG (via processing API). Sentinel-1: GeoTIFF (GRD) or complex data (SLC).

**How to access:**

```bash
# Register at https://dataspace.copernicus.eu/
# Use the OData API for searching:
curl "https://catalogue.dataspace.copernicus.eu/odata/v1/Products?\
\$filter=Collection/Name eq 'SENTINEL-2' and \
OData.CSC.Intersects(area=geography'SRID=4326;POINT(-105.0 40.0)') and \
ContentDate/Start gt 2023-06-01T00:00:00.000Z and \
ContentDate/Start lt 2023-08-31T00:00:00.000Z and \
Attributes/OData.CSC.DoubleAttribute/any(att:att/Name eq 'cloudCover' and att/OData.CSC.DoubleAttribute/Value lt 20.0)&\
\$top=10"

# Download with access token:
# 1. Get token from https://identity.dataspace.copernicus.eu/
# 2. Download product:
curl -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://zipper.dataspace.copernicus.eu/odata/v1/Products(PRODUCT_ID)/\$value" \
  -o product.zip
```

**GDAL direct access to Sentinel-2 COGs on AWS:**

```bash
# Sentinel-2 L2A COGs are available on AWS (no authentication needed)
gdalinfo /vsicurl/https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/2023/S2A_32TQM_20230701_0_L2A/TCI.tif
```

### NASA Earthdata / GIBS

**What:** NASA's Earthdata provides access to thousands of Earth science datasets. The Global Imagery Browse Services (GIBS) provides pre-rendered global imagery as map tiles via WMTS/WMS.

**Key datasets via Earthdata:**
- MODIS (Aqua/Terra): Land surface, vegetation, temperature, fires (250m-1km)
- VIIRS (Suomi NPP, NOAA-20): Day/night band, fires, vegetation (375-750m)
- ASTER: 15-90m multispectral
- SRTM: 30m elevation (terrain, out of scope but commonly co-used)

**Formats:** HDF4 (MODIS legacy), HDF5/NetCDF (newer products), GeoTIFF (some products).

**Earthdata access:**

```bash
# Register at https://urs.earthdata.nasa.gov/
# Search using CMR (Common Metadata Repository):
curl "https://cmr.earthdata.nasa.gov/search/granules.json?\
collection_concept_id=C2021957657-LPCLOUD&\
temporal[]=2023-06-01T00:00:00Z,2023-08-31T23:59:59Z&\
bounding_box=-105.5,39.5,-104.5,40.5&\
page_size=10"

# Download with .netrc authentication:
# Add to ~/.netrc:
#   machine urs.earthdata.nasa.gov login YOUR_USER password YOUR_PASS
curl -L -b ~/.urs_cookies -c ~/.urs_cookies -n \
  "https://e4ftl01.cr.usgs.gov/MOLT/MOD09GA.061/2023.07.01/MOD09GA.A2023182.h09v05.061.2023184041254.hdf" \
  -o MOD09GA.hdf
```

**GIBS WMTS for direct tile access:**

NASA GIBS serves pre-rendered global mosaics as map tiles, ideal for basemaps and quick visualization without downloading raw data.

```bash
# GIBS WMTS endpoint
# Base URL: https://gibs.earthdata.nasa.gov/wmts/epsg4326/best

# Get capabilities
curl "https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/wmts.cgi?SERVICE=WMTS&REQUEST=GetCapabilities"

# Fetch a single MODIS True Color tile (EPSG:4326)
curl -o tile.jpeg \
  "https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/MODIS_Terra_CorrectedReflectance_TrueColor/default/2023-07-01/250m/3/2/4.jpg"

# GIBS in Leaflet/OpenLayers:
# Template URL for EPSG:3857 (Web Mercator):
# https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/{Layer}/default/{Time}/{TileMatrixSet}/{z}/{y}/{x}.{format}
```

**Useful GIBS layers:**

| Layer | Identifier | Resolution | Format |
|---|---|---|---|
| MODIS True Color (Terra) | `MODIS_Terra_CorrectedReflectance_TrueColor` | 250m | JPEG |
| MODIS NDVI | `MODIS_Terra_NDVI_8Day` | 250m | PNG |
| VIIRS Night Lights | `VIIRS_SNPP_DayNightBand_ENCC` | 500m | PNG |
| Blue Marble | `BlueMarble_ShadedRelief_Bathymetry` | 500m | JPEG |

### OpenAerialMap

**What:** An open platform for hosting and accessing openly licensed aerial imagery. Community-contributed drone and aerial imagery with open licenses.

**Resolution:** Varies (typically sub-meter, often 5-20cm from drones).

**Coverage:** Spotty global coverage -- concentrated around disaster response areas, humanitarian mapping, and community contributions.

**Formats:** GeoTIFF (COG).

**API access:**

```bash
# Search imagery by bounding box
curl "https://api.openaerialmap.org/meta?\
bbox=-74.1,40.6,-73.8,40.8&\
resolution_from=0&resolution_to=1&\
limit=10"

# Response includes direct download URLs for COGs
# Each result has a "uuid" and direct GeoTIFF URL

# GDAL direct access to OAM imagery
gdalinfo /vsicurl/https://oin-hotosm.s3.amazonaws.com/SCENE_ID/SCENE_ID.tif
```

### AWS Open Data

**What:** Amazon hosts several major satellite imagery datasets on S3 with free egress (requester-pays for some). No AWS account needed for direct HTTP access; S3 CLI access is faster.

**Datasets:**

| Dataset | S3 Path | Resolution | Format | Auth Required |
|---|---|---|---|---|
| Landsat Collection 2 | `s3://usgs-landsat/` | 30m (MS), 15m (Pan) | COG | No (free) |
| Sentinel-2 L2A COGs | `s3://sentinel-cogs/` | 10-60m | COG | No (free) |
| Sentinel-2 (original) | `s3://sentinel-s2-l2a/` | 10-60m | JPEG2000 | Requester-pays |
| NAIP | `s3://naip-analytic/` | 0.6-1m | COG | Requester-pays |
| Sentinel-1 GRD | `s3://sentinel-s1-l1c/` | 5m (IW) | GeoTIFF | Requester-pays |
| Copernicus DEM (30m) | `s3://copernicus-dem-30m/` | 30m | COG | No (free) |

```bash
# Browse Landsat on S3 (no auth needed)
aws s3 ls --no-sign-request s3://usgs-landsat/collection02/level-2/standard/oli-tirs/2023/

# Download a specific Landsat scene band
aws s3 cp --no-sign-request \
  s3://usgs-landsat/collection02/level-2/standard/oli-tirs/2023/034/032/LC09_L2SP_034032_20230715_20230717_02_T1/LC09_L2SP_034032_20230715_20230717_02_T1_SR_B4.TIF \
  ./landsat_red.tif

# GDAL direct read from S3 (no download needed)
gdalinfo /vsis3/usgs-landsat/collection02/level-2/standard/oli-tirs/2023/034/032/LC09_L2SP_034032_20230715_20230717_02_T1/LC09_L2SP_034032_20230715_20230717_02_T1_SR_B4.TIF

# Read Sentinel-2 COGs directly via HTTP (no auth needed)
gdalinfo /vsicurl/https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/2023/S2A_32TQM_20230701_0_L2A/B04.tif

# NAIP via requester-pays (need AWS credentials)
aws s3 ls --request-payer requester s3://naip-analytic/co/2021/
```

### Google Earth Engine

**What:** Cloud platform for planetary-scale geospatial analysis with a massive public data catalog (petabytes). Processing runs server-side on Google infrastructure.

**Coverage:** Global, multi-petabyte catalog including Landsat (1972-present), Sentinel, MODIS, and hundreds of other collections.

**Access:** Free for research, education, and non-commercial use. Commercial use requires a paid Google Cloud project.

For detailed Earth Engine API usage, computation model, data catalog, and analysis patterns, see `earth-engine.md`.

**Key data catalog collections available in Earth Engine:**

| Collection | EE Dataset ID | Resolution |
|---|---|---|
| Landsat 8 SR | `LANDSAT/LC08/C02/T1_L2` | 30m |
| Landsat 9 SR | `LANDSAT/LC09/C02/T1_L2` | 30m |
| Sentinel-2 SR | `COPERNICUS/S2_SR_HARMONIZED` | 10-60m |
| Sentinel-1 GRD | `COPERNICUS/S1_GRD` | 10m |
| MODIS SR | `MODIS/061/MOD09GA` | 500m |
| MODIS Land Cover | `MODIS/061/MCD12Q1` | 500m |
| NAIP | `USDA/NAIP/DOQQ` | 0.6-1m |

### USGS NAIP (National Agriculture Imagery Program)

**What:** The USDA acquires aerial photography of the contiguous US during the agricultural growing season. NAIP provides orthorectified, natural-color and near-infrared imagery.

**Resolution:** 60cm (since 2018) or 1m (pre-2018). Four bands: Red, Green, Blue, NIR.

**Coverage:** Contiguous US. Acquired on a 2-3 year cycle per state.

**Formats:** MrSID (legacy), COG (newer), JPEG2000.

**How to access:**

| Source | Format | URL / Method |
|---|---|---|
| AWS S3 | COG | `s3://naip-analytic/` (requester-pays) and `s3://naip-visualization/` (free, RGB only) |
| USGS Earth Explorer | MrSID / JPEG2000 | Search "NAIP" dataset |
| Google Earth Engine | Cloud-hosted | `ee.ImageCollection('USDA/NAIP/DOQQ')` |
| Microsoft Planetary Computer | COG via STAC | `https://planetarycomputer.microsoft.com/api/stac/v1` |

```bash
# NAIP visualization tiles (free, no auth, RGB only)
aws s3 ls --no-sign-request s3://naip-visualization/co/2021/

# NAIP analytic tiles (4-band, requester-pays)
aws s3 ls --request-payer requester s3://naip-analytic/co/2021/

# GDAL direct read from NAIP visualization bucket
gdalinfo /vsis3/naip-visualization/co/2021/100cm/rgbir/39104/m_3910401_ne_13_060_20210903.tif
```

### Blue Marble and GEBCO

**Blue Marble:**

**What:** NASA's Blue Marble imagery is a composite satellite image of Earth's surface. Available as monthly or yearly composites. Excellent for basemaps and visual context.

**Resolution:** 500m/pixel (the "Next Generation" dataset at 21,600 x 10,800 pixels for the whole Earth).

**Download:**

```bash
# Blue Marble Next Generation (monthly, ~250 MB each)
# Available at: https://visibleearth.nasa.gov/collection/1484/blue-marble
# Direct download (July):
curl -L -o blue_marble_july.tif \
  "https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73776/world.topo.bathy.200407.3x5400x2700.png"

# Also available via NASA GIBS as a WMTS layer:
# Layer: BlueMarble_ShadedRelief_Bathymetry
```

**GEBCO (General Bathymetric Chart of the Oceans):**

**What:** Global ocean bathymetry and land topography dataset. Primarily for ocean floor mapping.

**Resolution:** 15 arc-seconds (~450m).

**Download:** Available at `https://www.gebco.net/data_and_products/gridded_bathymetry_data/`

**Formats:** NetCDF, GeoTIFF.

### Microsoft Planetary Computer

**What:** Microsoft's cloud-based geospatial data platform hosting major open datasets with STAC API access. Free tier available.

**Key datasets:** Landsat, Sentinel-2, NAIP, Copernicus DEM, ESA WorldCover, and more.

```bash
# Search via STAC API
curl "https://planetarycomputer.microsoft.com/api/stac/v1/search" \
  -H "Content-Type: application/json" \
  -d '{
    "collections": ["sentinel-2-l2a"],
    "bbox": [-105.5, 39.5, -104.5, 40.5],
    "datetime": "2023-06-01/2023-08-31",
    "query": {"eo:cloud_cover": {"lt": 20}},
    "limit": 5
  }'
```

---

## Commercial Imagery Providers

### Maxar (WorldView, GeoEye)

**Constellation:** WorldView-1/2/3, WorldView Legion (6 satellites), GeoEye-1.

**Resolution:** 30cm-class (pan), 1.24m (MS), 3.7m (SWIR on WV-3). WorldView Legion delivers 30cm-class imagery at up to 15 revisits/day for some locations.

**Revisit:** Multiple times per day (with full constellation).

**Products:**
- **Standard imagery**: Orthorectified, pan-sharpened
- **Stereo pairs**: For 3D point cloud and DSM generation
- **Living Library**: Archive of 125+ petabytes of historical imagery
- **HD/Native products**: Highest resolution, minimal processing

**Ordering/API:**
- **SecureWatch**: Online platform for browsing, ordering, and streaming
- **ARD (Analysis Ready Data)**: Pre-processed, atmospherically corrected tiles on AWS
- **GBDX / Maxar Geospatial Platform**: Developer APIs for search, order, and analysis

**Pricing:** Enterprise contracts, typically $10-25/km2 for archive, higher for fresh tasking. Government pricing differs (see Defense section).

### Airbus Defence and Space

**Constellation:** Pleiades (2 satellites, 50cm), Pleiades Neo (4 satellites, 30cm), SPOT 6/7 (1.5m).

**Resolution:** 30cm pan (Pleiades Neo), 50cm pan (Pleiades), 1.5m pan (SPOT).

**Revisit:** Daily (Pleiades Neo), 1-3 days (SPOT).

**Products:**
- **OneAtlas**: Cloud platform for searching, ordering, and streaming
- **Living Library**: Archive access
- **Analytics-ready products**: Ortho, pansharpened, bundle

**Ordering:** OneAtlas platform (`https://oneatlas.airbus.com/`), direct sales.

**Pricing:** Archive from ~$5/km2 (SPOT) to $15-25/km2 (Pleiades Neo). Tasking: premium.

### Planet (PlanetScope, SkySat)

**Constellation:** ~200 PlanetScope (Dove) satellites, ~20 SkySat satellites, Pelican (next-gen, 30cm).

**Resolution:** PlanetScope: 3.7m (8-band MS). SkySat: 50cm (pan), 80cm (MS), sub-meter video.

**Revisit:** PlanetScope: daily global coverage. SkySat: multiple times/day via tasking.

**Unique value:** Only provider offering daily global imaging at medium resolution. Enables time-series change detection at scale.

**Products:**
- **PlanetScope Basemaps**: Seamless global mosaics (monthly/quarterly)
- **SkySat Tasking**: On-demand high-resolution collection
- **SkySat Video**: 60-90 second full-motion video from orbit
- **Planet Analytic Feeds**: Pre-built change detection (building, road, ship, aircraft)

**API access:**

```bash
# Planet API (requires API key from https://www.planet.com/)
# Search PlanetScope imagery
curl -u "${PL_API_KEY}:" \
  "https://api.planet.com/data/v1/quick-search" \
  -H "Content-Type: application/json" \
  -d '{
    "item_types": ["PSScene"],
    "filter": {
      "type": "AndFilter",
      "config": [
        {"type": "GeometryFilter", "field_name": "geometry",
         "config": {"type": "Point", "coordinates": [-105.0, 40.0]}},
        {"type": "DateRangeFilter", "field_name": "acquired",
         "config": {"gte": "2023-06-01T00:00:00Z", "lte": "2023-08-31T00:00:00Z"}},
        {"type": "RangeFilter", "field_name": "cloud_cover", "config": {"lte": 0.2}}
      ]
    }
  }'
```

**Pricing:** Subscription-based. Education/research programs available. PlanetScope archive: ~$1-5/km2. SkySat tasking: ~$6-10/km2.

### BlackSky

**Constellation:** 16+ small satellites providing sub-1m electro-optical imagery.

**Resolution:** ~1m (panchromatic), multi-spectral.

**Revisit:** Up to 15 revisits/day for high-priority targets. Designed for rapid revisit/persistent monitoring.

**Unique value:** Combines satellite imagery with AI analytics and open-source intelligence. Optimized for low latency (imagery delivered within 90 minutes of collection).

**Ordering:** BlackSky Spectra platform. REST API available.

**Pricing:** Subscription and per-image. Government contracts (see Defense section).

### Capella Space

**Constellation:** ~10 SAR microsatellites (X-band).

**Resolution:** 0.3-0.5m (Spotlight mode), 1m (Stripmap).

**Unique value:** Commercial SAR at sub-50cm resolution, all-weather/day-night. Fastest SAR revisit of any commercial provider.

**Products:** SLC, GRD, GEC (Geocoded Ellipsoid Corrected). Change detection analytics.

**Ordering:** Capella Console (`https://console.capellaspace.com/`). API available.

### ICEYE

**Constellation:** ~30 SAR microsatellites (X-band).

**Resolution:** 25cm (Spot Fine), 0.5m (Spot), 1-3m (Strip, Scan).

**Unique value:** Largest commercial SAR constellation. Persistent monitoring with SAR. Flood monitoring and insurance analytics.

**Products:** SLC, GRD, amplitude imagery, change detection. Near real-time flood mapping.

### Satellogic

**Constellation:** 30+ satellites, expanding to 200+.

**Resolution:** Sub-1m (multispectral), hyperspectral (30m, 29 bands).

**Unique value:** Only commercial provider with both high-resolution multispectral AND hyperspectral from the same constellation.

**Products:** Multispectral, hyperspectral, full-motion video.

### Umbra

**Constellation:** 6+ SAR satellites (X-band).

**Resolution:** 16cm (Spotlight), highest commercially available SAR resolution.

**Unique value:** Highest-resolution commercial SAR available. Open data program provides free sample SAR imagery.

**Open data:** Umbra provides free SAR sample data at `https://umbra.space/open-data` -- useful for development and testing.

### 21AT / Jilin-1 (Chang Guang Satellite Technology)

**Constellation:** 130+ satellites (as of 2024), planned expansion to 300+.

**Resolution:** 0.5-0.75m (optical), video capability.

**Unique value:** Largest commercial optical constellation by satellite count. Video from space. Chinese-operated.

**Access:** Direct ordering through Chang Guang Satellite. Limited availability outside China/partner countries.

---

## Defense and Military Programs

### NGA (National Geospatial-Intelligence Agency)

The NGA is the primary US government agency for GEOINT (Geospatial Intelligence). NGA produces maps, charts, and geospatial analysis products for the Department of Defense and Intelligence Community.

**Key functions:**
- Acquires commercial satellite imagery for government use
- Produces and maintains geospatial datasets (aeronautical charts, nautical charts, geodetic products)
- Operates the National System for Geospatial Intelligence (NSG)
- Manages GEOINT standards (including NITF, the format used for intelligence imagery)

**Unclassified programs and products:**
- **GeoPackage / NSG standards**: NGA maintains OGC GeoPackage and other open standards
- **EGM2008**: Earth Gravitational Model (publicly available)
- **DTED (Digital Terrain Elevation Data)**: Terrain data at various classification levels
- **CIB (Controlled Image Base)**: Orthorectified imagery product (some levels unclassified)
- **GeoNames**: Geographic names database

### NRO (National Reconnaissance Office)

The NRO designs, builds, launches, and operates US reconnaissance satellites. NRO satellites provide the highest-resolution imagery available to the US government, significantly exceeding commercial capabilities.

**Relationship to NGA:** NRO collects the imagery; NGA processes, analyzes, and distributes it as GEOINT products.

**Declassified imagery:** Historical NRO imagery from the CORONA, GAMBIT, and HEXAGON programs (1960s-1980s) has been declassified and is available through USGS Earth Explorer. CORONA imagery provides ~2m resolution KH-4B coverage dating to the 1960s -- valuable for historical change analysis.

### GEOINT (Geospatial Intelligence)

GEOINT is intelligence derived from the exploitation and analysis of imagery and geospatial information. It encompasses:

- **IMINT (Imagery Intelligence)**: Analysis of satellite and aerial imagery
- **MASINT (Measurement and Signature Intelligence)**: Geospatially referenced technical intelligence
- **Geospatial data**: Maps, charts, geodetic data, gravity models

GEOINT analysis uses imagery at all resolutions, from commercial 30cm products to classified sub-10cm national systems.

### NIIRS (National Imagery Interpretability Rating Scale)

NIIRS is the standard for quantifying image quality in terms of what an analyst can interpret from the imagery. The scale runs from 0 (no useful information) to 9 (finest detail).

| NIIRS Level | GSD (approx.) | Interpretability |
|---|---|---|
| 0 | -- | Unusable |
| 1 | > 9m | Distinguish between urban and rural areas |
| 2 | 4.5-9m | Detect large buildings, road networks |
| 3 | 2.5-4.5m | Detect individual buildings, large vehicles |
| 4 | 1.2-2.5m | Identify vehicle types (car vs truck), detect small structures |
| 5 | 0.75-1.2m | Identify automobiles as sedans/wagons, detect individual railroad track |
| 6 | 0.4-0.75m | Distinguish between rotary and fixed-wing aircraft, identify construction equipment |
| 7 | 0.2-0.4m | Identify individual railroad ties, detect individual posts/poles |
| 8 | 0.1-0.2m | Identify vehicle make (Ford vs Toyota), detect individual rungs on ladders |
| 9 | < 0.1m | Identify bolts and rivets on vehicles, detect individual barbs on wire fences |

**The NIIRS to GSD relationship is approximate.** Actual interpretability depends on contrast, illumination angle, atmospheric conditions, and sensor MTF (Modulation Transfer Function), not just pixel size.

**Video NIIRS (V-NIIRS):** A parallel scale for full-motion video quality assessment.

**Radar NIIRS (RNIIRS):** Adapted scale for SAR imagery interpretability.

### Commercial-to-Military Imagery Programs

The US Department of Defense acquires commercial satellite imagery through major contract vehicles:

**EnhancedView (2010-2020):**
- Contract between NGA and DigitalGlobe (now Maxar)
- Guaranteed minimum purchase of commercial satellite imagery
- Funded development of WorldView-3 satellite
- Provided government access to Maxar's entire archive

**EOCL (Electro-Optical Commercial Layer, 2022+):**
- Successor to EnhancedView
- Multiple vendors: Maxar, BlackSky, Planet
- Estimated value: $3.2 billion (Maxar portion); total program value exceeds $4 billion across all vendors
- Provides government-wide access to commercial EO imagery
- Managed by NRO

**SDA (Space Development Agency) programs:**
- Proliferated LEO (Low Earth Orbit) architecture
- Integrating commercial imagery into military tactical networks

### Defense-Specific Provider Programs

**Maxar Defense:**
- **Direct Access Program (DAP)**: Dedicated ground stations for real-time satellite tasking and downlink
- **GEOINT Services**: Hosted analytics platform for government users
- **SecureWatch Government**: Classified-network access to Maxar imagery
- NIIRS 5-6 class imagery from WorldView constellation

**Planet Federal:**
- Government-specific licensing of daily global PlanetScope imagery
- SkySat tasking for high-resolution on-demand collection
- Analytic feeds (ship detection, building change, road change) for DoD users
- Operates under EOCL contract

**BlackSky Federal:**
- Rapid-revisit tactical imagery
- Low-latency delivery (< 90 minutes from collection to analyst)
- Integrated with AI analytics for automated change detection
- Operates under EOCL contract

### Classification Considerations

| Data Type | Classification | Notes |
|---|---|---|
| Commercial satellite imagery (< 30cm) | Generally unclassified | Purchased from commercial providers |
| NRO imagery | Classified (TS/SCI typically) | Highest resolution, national systems |
| Derived GEOINT products | Varies | Classification depends on source and analysis |
| NITF metadata | Can contain classified fields | TRE (Tagged Record Extensions) may have security markings |
| Targeting coordinates | Often classified | Even when derived from unclassified imagery |
| Collection deck / tasking priorities | Classified | Reveals intelligence priorities |
| Historical CORONA/GAMBIT imagery | Declassified | Available via USGS Earth Explorer |

**Key principle:** Even when the imagery itself is unclassified, the combination of imagery with targeting data, collection patterns, or analytical conclusions may be classified. Always handle GEOINT products according to their specific security markings, not assumptions about the source data.

---

## Imagery Marketplaces and Aggregators

### STAC (SpatioTemporal Asset Catalog)

STAC is an open specification for describing geospatial datasets, enabling standardized search and discovery across providers. It is the emerging standard for programmatic imagery discovery.

**STAC structure:**
- **Item**: A single spatiotemporal asset (one scene/granule) with geometry, datetime, and links to data files
- **Collection**: A group of related items (e.g., "Sentinel-2 L2A")
- **Catalog**: A top-level container of collections and items
- **STAC API**: RESTful search interface supporting spatial, temporal, and property filters

**Using STAC with GDAL:**

```bash
# GDAL has native STAC support via STACIT (Items) and STACTA (Tiled Assets) drivers
# Read a STAC item directly
gdalinfo "STACIT:\"https://planetarycomputer.microsoft.com/api/stac/v1/search?collections=sentinel-2-l2a&bbox=-105.5,39.5,-104.5,40.5&datetime=2023-07-01&limit=1\""
```

**Using STAC with Python (pystac-client):**

```python
from pystac_client import Client

# Connect to a STAC API
client = Client.open("https://planetarycomputer.microsoft.com/api/stac/v1")

# Search
results = client.search(
    collections=["sentinel-2-l2a"],
    bbox=[-105.5, 39.5, -104.5, 40.5],
    datetime="2023-06-01/2023-08-31",
    query={"eo:cloud_cover": {"lt": 20}},
    max_items=10
)

for item in results.items():
    print(item.id, item.properties["eo:cloud_cover"])
    # Access asset URLs
    print(item.assets["visual"].href)  # True color COG URL
```

**Major public STAC endpoints:**

| Provider | STAC API URL | Key Collections |
|---|---|---|
| Microsoft Planetary Computer | `https://planetarycomputer.microsoft.com/api/stac/v1` | Sentinel-2, Landsat, NAIP, Copernicus DEM |
| AWS Earth Search | `https://earth-search.aws.element84.com/v1` | Sentinel-2 COGs, Landsat COGs, NAIP |
| Radiant MLHub | `https://api.radiant.earth/mlhub/v1` | ML training datasets, labeled imagery |

### UP42

**What:** Geospatial marketplace and developer platform aggregating imagery from multiple providers (Airbus, Capella, 21AT, BlackSky, and others).

**Access model:** Credit-based. Purchase credits, use to order imagery and run processing tasks.

**Value:** Single API for accessing multiple providers. Built-in processing blocks (pansharpening, analytics, tiling). STAC-compatible catalog.

### SkyWatch / EarthCache

**What:** Simplified imagery ordering platform. Aggregates Airbus, Planet, Maxar, Capella, ICEYE, and others.

**Access model:** API-first platform. Define an area of interest and monitoring parameters; EarthCache automatically orders the best available imagery.

**Value:** Simplifies multi-provider ordering. Good for developers building applications that need automated imagery acquisition.

### Apollo Mapping

**What:** Imagery reseller providing access to Maxar, Airbus, Planet, and other archives.

**Value:** White-glove service for organizations that want someone else to handle imagery procurement. Useful for one-off purchases without setting up direct provider accounts.

---

## Data Formats and Delivery

### Delivery Methods by Provider

| Provider | Delivery Methods | Typical Formats |
|---|---|---|
| Maxar | Download (HTTPS/FTP), SecureWatch streaming, AWS S3 | GeoTIFF, NITF, JPEG2000 |
| Airbus | OneAtlas streaming, download, API | GeoTIFF, JPEG2000, DIMAP |
| Planet | API download, basemap tiles, S3 | GeoTIFF (COG), scenes as analytic/visual |
| BlackSky | API download, Spectra platform | GeoTIFF |
| Capella | Console download, API, S3 | GeoTIFF (GRD/GEC), HDF5 (SLC) |
| ICEYE | API download | GeoTIFF (GRD), HDF5 (SLC) |
| Sentinel (ESA) | Copernicus Data Space download/API | SAFE (JPEG2000), COG (via AWS) |
| Landsat (USGS) | Earth Explorer, AWS S3, Google Cloud | COG (Collection 2) |
| USGS NAIP | Earth Explorer, AWS S3 | COG, MrSID, JPEG2000 |
| NASA Earthdata | HTTPS download, OPeNDAP, GIBS tiles | HDF4, HDF5, NetCDF, GeoTIFF |

### Common Processing Levels

| Level | Description | Example |
|---|---|---|
| Level 0 | Raw instrument data, no processing | Raw SAR signal data |
| Level 1A | Reconstructed, unprocessed instrument data with radiometric calibration | Landsat L1TP (terrain corrected) |
| Level 1B/1C | Radiometrically corrected, geometrically registered | Sentinel-2 L1C (TOA reflectance) |
| Level 2 | Derived geophysical variables (surface reflectance, atmospherically corrected) | Landsat L2SP, Sentinel-2 L2A |
| Level 3 | Spatially/temporally aggregated (composites, mosaics) | MODIS monthly composites |
| ARD (Analysis Ready Data) | Provider-specific L2+ with consistent grid and projection | Maxar ARD, Planet Basemaps |

### Licensing and Usage Restrictions

**Common license types:**

| License Type | Can Redistribute? | Can Derive? | Examples |
|---|---|---|---|
| Open / Public Domain | Yes | Yes | Natural Earth, Landsat, Sentinel |
| Creative Commons (CC BY) | Yes (with attribution) | Yes | OpenAerialMap |
| Research/Education only | No (or limited) | For research | Earth Engine (free tier), some NASA datasets |
| Single end-user | No | Limited | Most commercial imagery |
| Enterprise / Government | Per contract | Per contract | Maxar, Planet contracts |

**Key restrictions to watch for:**
- **Commercial imagery**: Almost never redistributable. Cannot publish full-resolution imagery publicly. Thumbnails and low-res derivatives may be allowed.
- **Sentinel/Landsat**: Free and open. Can be redistributed and used commercially. Attribution requested.
- **NAIP**: Public domain (US government work). No restrictions.
- **Derived products**: Creating NDVI maps or classifications from restricted imagery may still be restricted -- check license terms.
- **Government/defense**: Additional handling requirements (ITAR, EAR, classification markings). NITF files may contain security metadata that must be respected.

### Converting Between Provider Formats

Most provider data can be standardized to COG for efficient serving:

```bash
# Sentinel-2 SAFE (JPEG2000) to COG
gdal_translate -of COG -co COMPRESS=DEFLATE \
  SENTINEL2_L2A.SAFE/GRANULE/.../IMG_DATA/R10m/T32TQM_20230701T103629_B04_10m.jp2 \
  sentinel2_b04_cog.tif

# NITF to COG
gdal_translate -of COG -co COMPRESS=JPEG -co QUALITY=90 \
  input.ntf output_cog.tif

# HDF5 (MODIS) to COG
gdal_translate -of COG -co COMPRESS=DEFLATE \
  HDF5:"MOD09GA.hdf"://MODIS_Grid_500m_2D/sur_refl_b01 \
  modis_b01_cog.tif

# MrSID to COG (requires MrSID GDAL plugin)
gdal_translate -of COG -co COMPRESS=JPEG -co QUALITY=85 \
  input.sid output_cog.tif
```

For detailed format specifications, compression options, and GDAL driver configuration, see `formats.md` and `gdal.md`.
