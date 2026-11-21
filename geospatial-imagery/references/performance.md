# Measure imagery performance

## Compare representative workloads

Measure warm tile hits, cold reads, reprojection/encoding, and multi-granule
renders separately. Fix the corpus, CRS and grid, output size and codec,
style, and request concurrency when comparing implementations. Include
both low-resolution overview reads and high-resolution windows. Record
which caches are warm, including the application, OS, and remote serving
layers that matter to the test.

Collect latency percentiles, throughput, errors, CPU, resident memory,
and concurrent work. For remote rasters also track request count and
bytes read. Measure time in lookup, read, decode, warp, composite, and
output encode. Choose budgets from the deployment's workload and
capacity.

## Match the change to the bottleneck

| Observation | Experiment |
|---|---|
| Many reads or excess bytes per request | Compare stored block sizes, overview levels, interleave, and grid alignment with the actual access pattern. Measure proxy or object-store range behavior. |
| Warp cost dominates | Compare preprocessing into a frequently served grid with on-demand warping. Keep the accuracy and validity policy fixed. |
| Encode cost dominates | Test output codecs and settings against representative imagery and consumer support. Measure response bytes and CPU together. |
| Duplicate cold renders | Coalesce identical requests or seed frequently reused tiles. Include data and style revisions in cache identity. |
| RSS saturates early | Cap simultaneous work and account for source buffers, decoder and application caches, warp memory, and metatiles together. |

Tune GDAL's block cache independently of warp memory. `GDAL_CACHEMAX`
controls the GDAL block cache per process and `gdalwarp -wm` controls
the warper's working-memory limit. Driver or warp thread options apply
to different stages. Bound total concurrency across requests and worker
threads. Ordinary GDAL handles should be used by one thread at a time
or opened separately per worker. GDAL 3.10 introduced an opt-in
thread-safe read-only raster API that can open separate underlying
datasets per thread. Account for their associated cache and handle costs.
[GDAL configuration](https://gdal.org/en/stable/user/configoptions.html),
[gdalwarp options](https://gdal.org/en/stable/programs/gdalwarp.html),
[GDAL thread safety](https://gdal.org/en/stable/user/multithreading.html).

A small cache or storage experiment should report which resources became
cheaper and whether fixture output, seam behavior, and validity stayed
within the accepted contract.
