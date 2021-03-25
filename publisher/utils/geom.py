from numpy import uint8
from rasterio import open as rasterio_open
from rasterio.features import shapes
from rasterio.warp import transform_geom
from shapely.geometry import box, mapping, MultiPolygon, Polygon, shape


def raster_extent(file_path: str, epsg: str='EPSG:4326') -> Polygon:
    """Get raster extent in arbitrary CRS.

    Args:
        file_path (str): Path to image
        epsg (str): EPSG Code of result crs
    Returns:
        dict: geojson-like geometry
    """
    with rasterio_open(file_path) as dataset:
        _geom = mapping(box(*dataset.bounds))
        return shape(transform_geom(dataset.crs, epsg, _geom, precision=6))


def raster_convexhull(file_path: str, epsg='EPSG:4326', nodata: int=0) -> dict:
    """Get footprint from any raster.

    Args:
        file_path (str): image file
        epsg (str): geometry EPSG
        nodata (int): Custom nodata value
    See:
        https://rasterio.readthedocs.io/en/latest/topics/masks.html
    """
    with rasterio_open(file_path) as dataset:
        # Read raster data, masking nodata values
        data = dataset.read(1)
        data[data != nodata] = 1
        data[data == nodata] = 0
        # Create mask, which 1 represents valid data and 0 nodata
        mask = data.astype(uint8)

        geoms = []
        res = {'val': []}
        for geom, val in shapes(mask, mask=mask, transform=dataset.transform):
            geom = transform_geom(dataset.crs, epsg, geom, precision=6)
            res['val'].append(val)
            geoms.append(shape(geom))

        if len(geoms) == 1:
            return geoms[0].convex_hull

        multi_polygons = MultiPolygon(geoms)

        return multi_polygons.convex_hull
