# GeoServer Architecture and Caching Reference

## Technology Stack

GeoServer is an open-source server for sharing geospatial data, built on the following stack:

- **Language**: Java (minimum Java 17 LTS as of GeoServer 2.28+)
- **Application Framework**: Spring Framework for dependency injection and request dispatch; Wicket for the web administration UI
- **Geospatial Library**: GeoTools -- provides data access, coordinate transforms, filtering, and rendering
- **Image Processing**: Eclipse ImageN (successor to JAI / Java Advanced Imaging); JAI-EXT for extended operations (nodata, ROI)
- **Image I/O**: Java ImageIO framework with extended readers/writers for geospatial formats (GeoTIFF, NetCDF, GRIB, etc.)
- **Build System**: Apache Maven with Bill of Materials (BOM) pattern for centralized dependency management across modules
- **Servlet Container**: Runs in any Java servlet container (Tomcat, Jetty)

### GeoServer 3 Modernization (In Progress)

GeoServer 3 is migrating to Spring Framework 7.0+, Spring Security 7.0+, Wicket 10, JakartaEE namespaces, and Eclipse ImageN 0.9+ (replacing legacy JAI 1.1.3). OpenRewrite is used for automated code migration.

### GeoServer Cloud

A separate deployment model built on Spring Boot with Spring Cloud technologies (service discovery, externalized configuration, distributed events, API gateway) for cloud-native, horizontally scalable deployments.

---

## Source Code Structure

The GeoServer codebase under `src/` follows a modular Maven layout. Key directories (verified from source):

| Directory | Purpose |
|---|---|
| `main/` | Core platform: `Catalog` interface, `StoreInfo`/`LayerInfo`/`StyleInfo` model, security, JAI config, coverage access |
| `platform/` | Shared utilities: `GeoServerExtensions`, `Service`, `Operation`, `GeoServerResourceLoader` |
| `ows/` | OWS `Dispatcher` (extends Spring `AbstractController`): routes requests by service/request/version to handlers |
| `wms-core/` | WMS implementation: `GetMap`, `GetMapRequest`, `GetFeatureInfo`, `WMSMapContent`, `RenderedImageMapOutputFormat` |
| `wms1_1/`, `wms1_3/` | WMS version-specific capabilities and request parsing |
| `wcs/`, `wcs2_0/` | Web Coverage Service 1.x and 2.0 implementations |
| `wfs-core/`, `wfs1_x/`, `wfs2_x/` | Web Feature Service implementations |
| `rest/` | REST API framework |
| `restconfig/` | REST configuration endpoints for workspaces, layers, stores |
| `gwc/` | GeoWebCache integration: `GWC` mediator, `CatalogLayerEventListener`, `CatalogStyleChangeListener` |
| `gwc-rest/` | GeoWebCache REST endpoints (seed, truncate, blobstores) |
| `web/` | Wicket-based web administration UI |
| `security/` | Authentication/authorization framework |
| `community/` | Community-contributed extensions |
| `extension/` | Official extensions |

Extensions can contribute new services, data formats, authentication providers, and admin UI pages through Spring's application context.

---

## Catalog Model

GeoServer's catalog is a hierarchical model of configuration objects persisted to the data directory as XML files. The `Catalog` interface is the central access point.

### Object Hierarchy

```
CatalogInfo (root marker interface)
  |
  |-- WorkspaceInfo
  |     |-- NamespaceInfo (1:1 with Workspace; provides XML namespace URI)
  |
  |-- StoreInfo (abstract; holds connection parameters, workspace reference)
  |     |-- DataStoreInfo (vector: PostGIS, Shapefile, GeoPackage, etc.)
  |     |-- CoverageStoreInfo (raster: getFormat(), getGridCoverageReader())
  |     |-- HTTPStoreInfo (abstract; remote services with capabilities URL, auth, connection pooling)
  |           |-- WMSStoreInfo (cascaded WMS)
  |           |-- WMTSStoreInfo (cascaded WMTS)
  |
  |-- ResourceInfo (abstract; dataset within a Store, identified by namespace + local name)
  |     |-- FeatureTypeInfo (vector resource from DataStore)
  |     |-- CoverageInfo (raster resource from CoverageStore)
  |
  |-- PublishedInfo (abstract; something that can appear in OGC services)
  |     |-- LayerInfo (publishes one ResourceInfo with default + alternate Styles)
  |     |-- LayerGroupInfo (ordered collection of Layers and/or nested LayerGroups)
  |
  |-- StyleInfo (SLD/SE or CSS document defining visual rendering rules)
```

### Key Relationships

- A **Workspace** is a container that groups related stores. Layers are referred to as `workspace:layername`.
- A **Namespace** provides the XML namespace URI for a workspace's resources (used in WFS/WCS responses).
- A **Store** holds connection parameters to a data source; it does not contain the data itself.
- A **Resource** (FeatureType or Coverage) represents a specific dataset within a store.
- A **Layer** publishes a resource for OGC service access. A resource can be published as multiple layers.
- A **Style** defines rendering rules. A layer has one default style and may have additional associated styles.
- Catalog objects are mutable but require an explicit `catalog.save(object)` call to persist changes.
- **Isolated Workspaces** restrict layer visibility to virtual service endpoints scoped to that workspace.

### Data Directory Layout

```
data_dir/
  global.xml                    # Global server settings
  logging.xml                   # Logging configuration
  workspaces/
    <workspace>/
      namespace.xml
      workspace.xml
      <datastore>/
        datastore.xml           # Connection parameters
        <featuretype>/
          featuretype.xml
          layer.xml
      <coveragestore>/
        coveragestore.xml
        <coverage>/
          coverage.xml
          layer.xml
  styles/
    <style>.sld                 # SLD documents
    <style>.xml                 # Style metadata
  layergroups/
    <group>.xml
  gwc-layers/                   # GeoWebCache tile layer configs
  security/                     # Security configuration
```

---

## Data Store Abstraction

GeoServer abstracts data access through the GeoTools DataAccess/DataStore SPI (Service Provider Interface) pattern:

- **DataStoreInfo** (vector): Extends `StoreInfo`. Connection parameters (JDBC URL, file path, etc.) are stored in `getConnectionParameters()`. The underlying GeoTools `DataStore` provides `FeatureSource`/`FeatureStore` objects for read/write access to feature collections. Implementations: PostGIS, Shapefile, GeoPackage, Oracle, SQL Server, etc.
- **CoverageStoreInfo** (raster): Extends `StoreInfo`. Provides `getFormat()` returning an `AbstractGridFormat` and `getGridCoverageReader()` returning a `GridCoverageReader`. The URL points to the raster source (file path, directory for mosaics, etc.). Implementations: GeoTIFF, ImageMosaic, NetCDF, GRIB, WorldImage, ArcGrid, etc.
- **HTTPStoreInfo** (cascaded remote services): Extends `StoreInfo` with `getCapabilitiesURL()`, authentication (username/password/authKey), connection pooling configuration (`maxConnections`, `readTimeout`, `connectTimeout`). Sub-interfaces `WMSStoreInfo` and `WMTSStoreInfo` cascade requests to remote OGC services.
- **StoreInfo** common features: All stores have `getName()`, `getWorkspace()`, `isEnabled()`, `getConnectionParameters()`, `getMetadata()`, and `isDisableOnConnFailure()` (auto-disable on connection errors).

The abstraction means GeoServer treats all data sources uniformly through common interfaces, regardless of whether data resides in a database, on a file system, or on a remote server.

---

## WMS Rendering Pipeline

When GeoServer receives a WMS GetMap request, it passes through the following stages:

### 1. Request Dispatch
The OWS `Dispatcher` (in `src/ows/`, extends Spring `AbstractController`) receives the HTTP request. It parses the `service`, `request`, and `version` parameters (from KVP query string or XML POST body) and locates the matching `Service` descriptor. The `request` parameter identifies the operation (e.g., `GetMap`), which is dispatched via `DispatcherCallback` hooks.

### 2. Request Parsing
KVP parsers assemble a `GetMapRequest` object from query parameters: layers, styles, BBOX, SRS/CRS, width, height, format, TIME, ELEVATION, and vendor parameters (`CQL_FILTER`, `ENV`, `SLD_BODY`).

### 3. Map Content Assembly
`GetMap.run()` (in `src/wms-core/`) creates a `WMSMapContent` and for each requested layer:
- Resolves the layer from the catalog
- Loads the associated style (default or requested)
- Detects tiled requests and wraps the output format in `MetatileMapOutputFormat` for on-the-fly metatiling
- Handles TIME and ELEVATION dimension parameters for multidimensional data

### 4. Style Evaluation
The SLD/SE style is evaluated:
- Scale denominators are computed to determine which rules are active at the requested zoom
- Filter expressions in rules are evaluated against feature/coverage attributes
- For rasters: RasterSymbolizer elements (ColorMap, ContrastEnhancement, ChannelSelection) define how pixel values map to colors
- Rendering transformations (if any) are applied as a pre-processing step

### 5. Data Reading
- Vector layers: FeatureSource queries the underlying store with spatial filter (BBOX) and attribute filter
- Raster layers: GridCoverageReader reads the relevant portion of the coverage at appropriate resolution, potentially using overviews for reduced resolution requests

### 6. Rendering
`RenderedImageMapOutputFormat` (in `src/wms-core/.../map/`) instantiates GeoTools `StreamingRenderer`, configures it with `WMSMapContent`, Java2D hints, and a thread pool, then invokes `renderer.paint()`:
- Iterates over layers and features/coverages
- Applies symbolizers to produce Java2D graphics operations on a `BufferedImage`
- Uses Eclipse ImageN (`org.eclipse.imagen`) for image manipulation (confirmed in imports)
- Interpolation modes per layer: Nearest, Bilinear, Bicubic (from `LayerInfo.WMSInterpolation`)
- A **rendering buffer** (configurable via `LayerInfo.BUFFER`) extends the rendering area beyond tile boundaries to prevent label/symbol clipping

### 7. Encoding
The rendered image is encoded to the requested format (PNG, JPEG, GIF, TIFF, etc.) using the appropriate encoder. GeoServer offers multiple PNG encoders with different speed/compression tradeoffs.

### 8. Response
The encoded image is written to the HTTP response with appropriate content-type headers.

---

## ImageMosaic Plugin

The ImageMosaic plugin is GeoServer's primary mechanism for combining multiple raster files into a single logical coverage layer. It is essential for managing large collections of imagery tiles, time-series data, or multi-resolution datasets.

### Core Concepts

- **Granule**: An individual raster file within the mosaic
- **Index**: A spatial index (shapefile or database table) that maps each granule's bounding polygon to its file path
- **Heterogeneous mosaics**: Supports granules with different CRSs and color models (gray, RGB, RGBA, indexed), though mixing scientific data types (float/double) with color data is not allowed

### Configuration Files

All files are placed in the mosaic root directory:

| File | Purpose |
|---|---|
| `<name>.properties` | Main mosaic config: resolution levels, absolute paths, location attribute, caching |
| `indexer.properties` | Schema definition, property collectors, time/elevation attributes, recursive scanning |
| `datastore.properties` | Index store backend: shapefile (default), PostGIS, Oracle, H2, SQL Server |
| `timeregex.properties` | Regex for extracting time values from file names |
| `elevationregex.properties` | Regex for extracting elevation values from file names |
| `<name>.sld` | Optional default style |

### indexer.properties Key Parameters

- **Schema**: Comma-separated attribute definitions (e.g., `location:String,ingestion:java.util.Date,elevation:Double,the_geom:Polygon`)
- **PropertyCollectors**: Extractors that parse filenames (e.g., `TimestampFileNameExtractorSPI[timeregex](ingestion)`)
- **TimeAttribute / ElevationAttribute**: Designate which attributes represent time and elevation dimensions
- **AdditionalDomainAttributes**: Custom dimensions beyond time/elevation
- **Recursive**: Scan subdirectories (default: true)
- **MosaicCRS**: Target CRS for heterogeneous mosaics
- **UseExistingSchema**: Use pre-existing database schema rather than creating one

### Property Collectors

Extract metadata from filenames via regex:
- `TimestampFileNameExtractorSPI` -- temporal values
- `DoubleFileNameExtractorSPI`, `IntegerFileNameExtractorSPI` -- numeric values
- `CRSExtractorSPI` -- coordinate reference system info
- `CurrentDateExtractorSPI`, `FSDateExtractorSPI` -- date from file system metadata

### Coverage Parameters

| Parameter | Description |
|---|---|
| `FootprintBehavior` | How to handle regions outside granule footprints: `None`, `Cut` (clip), `Transparent` (alpha) |
| `InputTransparentColor` | Color to treat as transparent when reading granules |
| `OutputTransparentColor` | Color to make transparent in final output |
| `MergeBehavior` | Overlap handling: `FLAT` (topmost), `STACK` (band stacking), `MIN`, `MAX` |
| `MaxAllowedTiles` | Limit on simultaneous granule reads to prevent resource exhaustion |
| `USE_IMAGEN_IMAGEREAD` | Deferred (`true`) vs immediate (`false`) reading; deferred saves memory |
| `Caching` | In-memory index caching; set `false` for large or actively ingested mosaics |

### Time and Elevation Dimensions

ImageMosaic supports WMS TIME and ELEVATION dimensions, enabling queries like:
```
GetMap?...&TIME=2024-01-15T00:00:00Z&ELEVATION=500
```
GeoServer uses the index table to select only the granules matching the requested time/elevation, allowing efficient access to specific slices of multidimensional data.

---

## REST API

GeoServer exposes a comprehensive REST API for programmatic configuration management. All operations use standard HTTP methods: GET (read), POST (create), PUT (update), DELETE (remove).

### URL Pattern

```
http://<host>:<port>/geoserver/rest/<resource-path>
```

### Key Endpoint Groups

| Resource | Endpoint Pattern | Operations |
|---|---|---|
| Workspaces | `/rest/workspaces[/<ws>]` | CRUD on workspaces |
| Namespaces | `/rest/namespaces[/<ns>]` | CRUD on namespaces |
| Data Stores | `/rest/workspaces/<ws>/datastores[/<ds>]` | CRUD on vector stores |
| Feature Types | `/rest/workspaces/<ws>/datastores/<ds>/featuretypes[/<ft>]` | CRUD on vector layers |
| Coverage Stores | `/rest/workspaces/<ws>/coveragestores[/<cs>]` | CRUD on raster stores |
| Coverages | `/rest/workspaces/<ws>/coveragestores/<cs>/coverages[/<c>]` | CRUD on raster layers |
| Layers | `/rest/layers[/<layer>]` | CRUD on published layers |
| Layer Groups | `/rest/layergroups[/<lg>]` | CRUD on layer groups |
| Styles | `/rest/styles[/<style>]` | CRUD on SLD/CSS styles |
| WMS Stores | `/rest/workspaces/<ws>/wmsstores[/<wms>]` | Cascaded WMS |
| WMTS Stores | `/rest/workspaces/<ws>/wmtsstores[/<wmts>]` | Cascaded WMTS |
| Settings | `/rest/settings` | Global server settings |
| Logging | `/rest/logging` | Logging configuration |
| Security | `/rest/security/...` | Roles, users, access rules |
| ImageMosaic | `/rest/workspaces/<ws>/coveragestores/<cs>/coverages/<c>/index[/granules]` | Granule management |
| GeoWebCache | `/rest/seed/<layer>`, `/rest/blobstores`, etc. | Tile cache operations |

### Content Negotiation

Endpoints accept and return JSON or XML based on the `Accept` and `Content-Type` headers, or via file extension (e.g., `.json`, `.xml`).

### File Upload

Data stores support file upload via PUT with content types like `application/zip` (Shapefile), `image/tiff` (GeoTIFF), etc. Modes: `file` (upload), `url` (reference), `external` (filesystem path).

---

## SLD/SE Raster Styling

Raster data is styled using `<RasterSymbolizer>` within an SLD document. Key sub-elements:

### Opacity
```xml
<Opacity>0.75</Opacity>
```
Values from 0 (transparent) to 1 (opaque).

### ChannelSelection
Maps dataset bands to display channels:
```xml
<ChannelSelection>
  <RedChannel><SourceChannelName>4</SourceChannelName></RedChannel>
  <GreenChannel><SourceChannelName>3</SourceChannelName></GreenChannel>
  <BlueChannel><SourceChannelName>2</SourceChannelName></BlueChannel>
</ChannelSelection>
```
Dynamic band selection via `env` functions enables multispectral/hyperspectral imagery exploration at request time.

### ColorMap
Maps pixel values to colors. Three types:

- **`type="ramp"`** (default): Interpolates between entries to create gradients
- **`type="intervals"`**: Discrete color blocks, no interpolation
- **`type="values"`**: Only exact matches rendered; all other values transparent

```xml
<ColorMap type="ramp">
  <ColorMapEntry color="#0000FF" quantity="0" label="Low"/>
  <ColorMapEntry color="#00FF00" quantity="50" label="Medium"/>
  <ColorMapEntry color="#FF0000" quantity="100" label="High"/>
</ColorMap>
```

ColorMapEntry attributes support CQL expressions for dynamic styling:
```xml
<ColorMapEntry color="#00FF00" quantity="${env('threshold',50)}" label="Dynamic"/>
```

### ContrastEnhancement

- **Normalize**: Stretches value range to fill 0-255
- **Histogram**: Equalizes pixel distribution across brightness levels
- **GammaValue**: Brightness scaling factor (<1 darkens, >1 brightens)

Vendor options for Normalize provide fine-grained control:
- `StretchToMinimumMaximum`: Linear stretch from [min, max] to [0, 255]
- `ClipToMinimumMaximum`: Clamp values outside [min, max]
- `ClipToZero`: Values outside range become 0

```xml
<ContrastEnhancement>
  <Normalize>
    <VendorOption name="algorithm">StretchToMinimumMaximum</VendorOption>
    <VendorOption name="minValue">10</VendorOption>
    <VendorOption name="maxValue">240</VendorOption>
  </Normalize>
</ContrastEnhancement>
```

---

## Security Model

GeoServer implements role-based access control (RBAC) at multiple levels:

### Authentication
Supports HTTP Basic, Digest, form-based login, certificate-based, and LDAP/Active Directory authentication. Authentication filters and providers are configurable.

### Authorization Layers

1. **Service-level security** (`services.properties`): Controls access to entire OGC services or specific operations (e.g., WFS-T write access)
   - Pattern: `<service>.<operation>=<role>[,<role>,...]`
   - Example: `wfs.Transaction=ROLE_EDITOR`

2. **Layer-level security** (`layers.properties`): Controls read/write/admin access per layer or workspace
   - Pattern: `<workspace>.<layer>.<permission>=<role>[,<role>,...]`
   - Permission types: `r` (read), `w` (write), `a` (admin)
   - Example: `topp.states.r=ROLE_VIEWER`
   - Wildcard: `*.*.r=*` grants read access to all layers for all roles

3. **REST API security**: Configured separately to control who can modify server configuration

### Limitation

Layer-level and service-level security cannot be combined in a single rule. You cannot, for example, restrict WMS access to a specific layer while allowing WFS access to the same layer for a different role in one rule.

### GeoWebCache Security

When data security is enabled, GeoWebCache verifies user access before serving cached tiles. WMS-C requests inherit WMS security rules; other GWC services use rules associated with the "GWC" service.

---

## GeoWebCache (GWC) Tile Caching

### Architecture

GeoWebCache is a tile caching engine that sits between map clients and the map server. It is available in two deployment modes:

- **Embedded in GeoServer**: Automatically configured; all GeoServer layers are available for caching with no setup required. Tile layer configs are stored in `<data_dir>/gwc-layers/` as individual XML files.
- **Standalone**: Separate deployment that can proxy any WMS-compatible server. Recommended for multi-instance GeoServer deployments.

### Request Flow

1. Client sends a tile request (WMTS, TMS, or WMS-C with `tiled=true`)
2. GWC checks if the requested tile exists in the cache (BlobStore lookup by layer/gridset/zoom/x/y)
3. **Cache hit**: Return the cached tile directly (fast path)
4. **Cache miss**: Forward request to GeoServer's WMS renderer, cache the generated tile, and return it

### Tile Grid Sets

A gridset defines the tiling scheme: CRS, extent, tile dimensions, and zoom levels.

**Pre-configured gridsets:**
- `EPSG:4326` (geographic): 22 zoom levels, 256x256 pixels
- `EPSG:900913` / `EPSG:3857` (Web Mercator): 31 zoom levels, 256x256 pixels
- Additional gridsets from the OGC Tile Matrix Set specification

**Custom gridsets** can be defined with:
- Any CRS GeoServer recognizes
- Custom tile dimensions
- Custom zoom level count and resolution hierarchy
- `alignTopLeft` setting for tile origin

Each zoom level typically doubles in both dimensions (4x tile count). After creating a custom gridset, it must be assigned to specific layers.

### Metatiling

A **metatile** combines multiple tiles into a single backend render request:
- Default: **4x4** metatile (16 tiles rendered as one image, then sliced)
- Reduces redundant rendering at tile boundaries
- Prevents labels and symbols from being clipped at tile edges
- **Gutter**: Extra pixels rendered beyond metatile boundaries to handle symbol/label overflow; configurable in pixels

Trade-off: Larger metatiles reduce boundary artifacts but increase memory usage per render request.

### Seeding, Reseeding, and Truncating

- **Seed**: Pre-generate tiles for specified zoom levels and grid subsets (spatial bounds). Tiles are only generated where they do not already exist.
- **Reseed**: Regenerate tiles even if they already exist in the cache. Useful after source data updates.
- **Truncate**: Remove cached tiles for a layer, optionally filtered by zoom level, grid subset, or parameter filters.

Operations can be monitored and managed through the web UI or REST API (`/rest/seed/<layer>`). Multiple seed/truncate tasks can run concurrently.

### BlobStore Interface

The BlobStore abstraction handles tile persistence. Implementations:

| BlobStore | Storage | Key Structure |
|---|---|---|
| **File** | Local filesystem | Directory hierarchy: `<cache_dir>/<layer>/<gridset>/<zoom>/<x>/<y>.<ext>` |
| **S3** | Amazon S3 bucket | TMS-like: `[prefix]/<layer>/<gridset>/<format>/<params>/<z>/<x>/<y>.<ext>` |
| **Azure** | Azure Blob container | TMS-like (same pattern as S3) |
| **GCS** | Google Cloud Storage | TMS-like (same pattern as S3) |
| **MBTiles** | SQLite database | MBTiles specification |
| **Swift** | OpenStack Swift | TMS-like (same pattern as S3) |

#### Multi-BlobStore Configuration

- Multiple blobstores can coexist; each has a unique `id`
- Exactly one must be marked `default="true"` for unassigned layers
- Layers can be explicitly assigned to a specific blobstore via `blobStoreId`
- Configured in `geowebcache.xml`
- File BlobStore requires `baseDirectory` (absolute path) and optional `fileSystemBlockSize` (default 4096)

### Cache Expiration and Invalidation

- **Event-driven automatic truncation**: GeoServer's GWC integration module registers two `CatalogListener` implementations that automatically truncate cached tiles on catalog changes:
  - `CatalogLayerEventListener`: Truncates tiles when a layer's default style changes, when a layer group's layers/styles change, when a `FeatureTypeInfo` CQL filter changes, and when cached alternate styles are removed. Automatically creates `GeoServerTileLayer` entries when new layers are published.
  - `CatalogStyleChangeListener`: Monitors style modifications and updates STYLES parameter filters on affected tile layers
- **Manual truncation**: Explicit seed/reseed/truncate operations via web UI or REST API
- **HTTP cache headers**: Configurable Last-Modified and Cache-Control headers on tile responses (driven by `ResourceInfo.CACHE_AGE_MAX` metadata)
- **In-memory cache eviction**: Policies include `EXPIRE_AFTER_WRITE`, `EXPIRE_AFTER_ACCESS`, and `NULL` (no in-memory caching)
- **Parameter filters**: Allow caching the same layer with different parameter values (e.g., TIME, STYLES); each unique parameter combination creates a separate cache set

### Disk Quota Management

Controls total disk usage for cached tiles:

- **Disabled by default**; enabled via `geowebcache-diskquota.xml` in the cache directory
- Quotas can be set globally or per-layer with magnitude + units (B, KiB, MiB, GiB, TiB)
- **Eviction policies**:
  - **LFU (Least Frequently Used)**: Evicts tiles with the fewest access counts
  - **LRU (Least Recently Used)**: Evicts tiles that haven't been accessed for the longest time
- Usage statistics are tracked in an embedded Berkeley DB Java Edition database (`diskquota_page_store/` directory)
- Eviction operates on "pages" of tiles rather than individual tiles for efficiency

---

## Image Processing Chain

### Eclipse ImageN (formerly JAI)

Eclipse ImageN provides tile-based image processing, meaning large images are processed as a grid of smaller tiles without loading the entire image into memory.

**Key concepts:**
- **Tile cache**: Global cache of processed image tiles; configured as a percentage of JVM heap (0 to 1 exclusive)
- **Operation chaining**: Image operations are composed into a processing graph (lazy evaluation); tiles are computed on demand
- **Tile recycling**: Reuses allocated tile buffers to reduce GC pressure
- **Tile threads**: Configurable thread count for parallel tile computation
- **Native acceleration**: ImageN can use platform-native code for faster processing when available

### JAI-EXT

A pure-Java replacement for JAI operations with critical enhancements for geospatial processing:
- **NoData handling**: Operations correctly propagate and handle nodata values
- **Region of Interest (ROI)**: Operations can be constrained to specific regions, avoiding processing of masked/invalid areas
- **No native library dependency**: Pure Java implementation, eliminating platform-specific native library issues

### ImageIO Framework

Provides pluggable image readers and writers:
- **Readers**: GeoTIFF, NetCDF, GRIB, JPEG2000, PNG, HDF, ECW, MrSID
- **Writers**: PNG (multiple encoders), JPEG, GeoTIFF, etc.
- **Deferred reading**: `USE_IMAGEN_IMAGEREAD=true` defers pixel reads until tiles are actually needed, reducing memory for large coverages (risk: too many open file handles)

### Coverage Processing Pipeline

For raster/coverage data, the processing chain is:
1. **Read**: GridCoverageReader loads the requested spatial extent, possibly using overviews for reduced resolution
2. **Band selection**: ChannelSelection in SLD picks specific bands
3. **Reprojection**: If the request CRS differs from the native CRS, the coverage is reprojected (interpolation method: nearest neighbor, bilinear, or bicubic)
4. **Rendering transformation**: Optional pre-processing (e.g., contour generation, heatmap, NDVI calculation)
5. **Symbolization**: RasterSymbolizer applies color mapping, contrast enhancement, and opacity
6. **Encoding**: Final image encoded to requested output format

---

## Performance Tuning

### JVM Settings

```
-Xms4g -Xmx4g                          # Heap: set min=max for stability
-XX:+UseParallelGC                      # Parallel GC for multi-core (or G1GC)
-Xss512k                                # Stack size (each request = 1 thread)
```

- **Heap sizing**: For coverage serving, more heap improves performance (tile cache benefits). For vector-only serving, streaming means extra heap has less impact. Typical range is 2-4 GB; larger heaps may benefit coverage-heavy workloads but require appropriate GC selection.
- **GC selection**: G1GC is recommended as the general-purpose default (also the JVM default since Java 9). ParallelGC is acceptable for simpler workloads. Only one GC algorithm should be active.
- **Thread model**: Each GeoServer request gets its own thread, consuming heap memory for data loading rather than stack memory.

### Eclipse ImageN / JAI Configuration

| Setting | Recommended | Notes |
|---|---|---|
| Memory Capacity | 0.75 (75% of heap) | Default is 0.5; increase to 0.75 for coverage-heavy workloads |
| Memory Threshold | 0.75 | Retention threshold during tile eviction |
| Tile Threads | 2x CPU cores | Parallel tile computation |
| Tile Recycling | Enabled | Reduces GC pressure from tile allocation |

### Coverage Access Settings

| Setting | Purpose |
|---|---|
| Core Pool Size | Minimum threads for ImageMosaic parallel reads |
| Maximum Pool Size | Upper limit on concurrent granule read threads |
| Keep Alive Time | Idle thread timeout |
| ImageIO Cache Threshold | Below threshold: in-memory encoding; above: file-based (set higher for small WMS tiles, lower for large WCS responses) |

### Connection Pooling

For database-backed coverage indexes (PostGIS ImageMosaic index, etc.):
- Configure connection pool min/max in the datastore.properties
- Pool size should account for concurrent WMS requests multiplied by potential parallel granule reads

### Coverage Access Optimization

| Optimization | Description |
|---|---|
| **Overviews** | Pre-computed reduced-resolution representations; GeoServer automatically selects the closest overview to the requested resolution |
| **Footprint management** | `FootprintBehavior` controls how no-data regions are handled; `Transparent` adds alpha channel overhead |
| **Input/Output limits** | WCS limits on read and response image sizes prevent resource exhaustion |
| **Max Oversampling Factor** | `-Dorg.geotools.coverage.max.oversample=N` limits reprojection oversampling to prevent memory blowup |
| **Tiled GeoTIFF** | Source data should be internally tiled (not stripped) for efficient partial reads |
| **Index caching** | `Caching=true` in mosaic properties keeps spatial index in memory; disable for very large or actively changing mosaics |

### Output Format Selection

- **JPEG**: Smallest file size, fastest encoding; lossy; best for imagery/aerial photos
- **PNG8**: Good compression, transparency support; best for categorical/thematic maps
- **PNG24**: Lossless with transparency; larger files
- **GIF**: Legacy format; limited to 256 colors

---

## Architectural Patterns for Imagery Serving

GeoServer's architecture demonstrates several patterns relevant to building imagery servers:

1. **Catalog-driven configuration**: All layer metadata, connections, and styles are managed through a structured catalog with well-defined object types and relationships, rather than ad-hoc file/database configurations.

2. **Store abstraction**: Data source connections are abstracted behind uniform interfaces (DataStore, CoverageStore), allowing the rendering pipeline to be agnostic about the underlying storage format or location.

3. **Lazy tile-based processing**: The image processing chain uses deferred evaluation and tile-based computation, so only the pixels actually needed for the response are read and processed.

4. **Multi-tier caching**: The GeoWebCache layer provides pre-rendered tile caching with pluggable storage backends, while the ImageN tile cache provides in-memory caching of intermediate processing results.

5. **Metatile rendering**: Combining multiple client tiles into a single backend render request reduces per-tile overhead and eliminates boundary artifacts.

6. **Pluggable BlobStore**: The tile storage abstraction supports filesystem, cloud object storage (S3, Azure, GCS), and database backends, allowing cache placement to match deployment architecture.

7. **Dimension-aware mosaic indexing**: The ImageMosaic pattern of maintaining a spatial/temporal/elevation index over granules enables efficient access to specific slices of large multidimensional datasets.

8. **Style-driven rendering**: Decoupling data from visualization through SLD/SE styles allows the same dataset to be rendered in multiple ways without data duplication.
