from unittest import mock, TestCase

from pandas import read_csv, to_datetime
from pandas.testing import assert_frame_equal

from publisher.environment import PR_BASE_DIR, PR_FILES_PATH, PR_TASK_CHUNKS
from publisher.model import PostgreSQLCatalogTestConnection, PostgreSQLPublisherConnection
from publisher.publisher import generate_chunk_params, SatelliteMetadata
from publisher.util import PublisherWalk
from publisher.validator import validate, QUERY_SCHEMA
from publisher.workers import CELERY_TASK_QUEUE, process_items


db = PostgreSQLCatalogTestConnection()
db_publisher = PostgreSQLPublisherConnection()


class BaseTestCases:
    class BaseTestCase(TestCase):

        def setUp(self):
            # clean tables before each test case
            db.delete_from_items()
            db_publisher.delete_from_task_error()

        @staticmethod
        def read_item_from_csv(file_name):
            expected = read_csv(f'tests/api/{file_name}')

            expected['start_date'] = to_datetime(expected['start_date'])
            expected['end_date'] = to_datetime(expected['end_date'])
            expected['assets'] = expected['assets'].astype('str')
            expected['metadata'] = expected['metadata'].astype('str')

            return expected

        def check_if_the_items_have_been_added_in_the_database(self, expected_file_path):
            # get the result from database
            result = db.select_from_items()
            # get the expected result
            expected = BaseTestCases.BaseTestCase.read_item_from_csv(expected_file_path)
            assert_frame_equal(expected, result)

        def check_if_the_items_table_is_empty(self):
            # check if the result size is equals to 0
            self.assertEqual(0, len(db.select_from_items().index))

        def check_if_the_errors_have_been_added_in_the_database(self, expected):
            # get the result from database
            result = db_publisher.select_from_task_error()
            self.assertEqual(expected, result)


class PublisherOkTestCase(BaseTestCases.BaseTestCase):

    @mock.patch('publisher.workers.celery_config.task_always_eager', False)
    def test__publisher__ok__empty_query(self):
        self.maxDiff=None

        expected = [
            {
                'message': 'There is metadata to the `CBERS2B_XYZ_L2_DN` collection, however this collection does not exist in the database.',
                'metadata': {'collection': 'CBERS2B_XYZ_L2_DN'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a DN XML file in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2016_01/CBERS_4_MUX_DRD_2016_01_01.13_28_32_CB11/157_101_0/2_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a DN XML file in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2020_07/CBERS_4_MUX_DRD_2020_07_31.13_07_00_CB11/155_103_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a DN XML file in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4A/2019_12/CBERS_4A_MUX_RAW_2019_12_28.14_15_00/221_108_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_CCD_20070925.145654/181_096_0/2_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_HRC_20070929.124300/145_C_111_3_0/2_BC_UTM_WGS84'},
                'type': 'warning',
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_WFI_20070928.131338/154_124_0/2_BC_LCC_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT1/1976_10/LANDSAT1_MSS_19761002.120000/010_057_0/2_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT2/1975_07/LANDSAT2_MSS_19750724.123000/230_070_0/2_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT3/1982_08/LANDSAT3_MSS_19820802.120000/231_072_0/2_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT5/1984_04/LANDSAT5_TM_19840406.124930/223_062_0/2_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990719.124008/217_064_0/2_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT7/2003_06/LANDSAT7_ETM_20030601.125322/220_061_0/2_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a TIFF file in this folder that ends with the `BAND13.tif` template, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_135_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a TIFF file in this folder that ends with the `BAND13.tif` template, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_136_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a TIFF file in this folder that ends with the `BAND13.tif` template, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_137_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a TIFF file in this folder that ends with the `CMASK_GRID_SURFACE.tif` template, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_137_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4/2021_02/CBERS_4_PAN10M_DRD_2021_02_02.01_32_45_CB11/073_113_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4A/2020_04/CBERS_4A_MUX_RAW_2020_04_06.00_56_20_CP5/164_025_0/0_NN_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4A/2020_04/CBERS_4A_MUX_RAW_2020_04_06.00_56_20_CP5/164_025_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4A/2020_04/CBERS_4A_WPM_RAW_2020_04_01.13_18_58_ETC2/202_112_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4A/2020_06/CBERS_4A_MUX_RAW_2020_06_03.15_18_00_ETC2/239_112_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4A/2020_08/CBERS_4A_WPM_RAW_2020_08_15.13_54_30_ETC2/212_107_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4A/2020_08/CBERS_4A_WPM_RAW_2020_08_17.03_52_45_ETC2/373_019_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4A/2021_01/CBERS_4A_MUX_RAW_2021_01_01.13_48_30_ETC2/209_105_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4A/2021_01/CBERS_4A_MUX_RAW_2021_01_01.13_48_30_ETC2/209_110_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4A/2021_01/CBERS_4A_MUX_RAW_2021_01_10.13_24_30_ETC2/201_109_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            }
        ]

        _, query, _ = validate({}, QUERY_SCHEMA)

        # p_walk is a generator that returns just valid directories
        p_walk = PublisherWalk(PR_BASE_DIR, query, SatelliteMetadata())

        # get all available collections from CSV file
        df_collections = read_csv(f'{PR_FILES_PATH}/collections.csv')

        # run the tasks by chunks. PR_TASK_CHUNKS chunks are sent to one task
        tasks = process_items.chunks(
            generate_chunk_params(p_walk, df_collections), PR_TASK_CHUNKS
        ).apply_async(queue=CELERY_TASK_QUEUE)

        # wait all chunks execute
        tasks.get()

        # save the errors in the database
        p_walk.save_the_errors_in_the_database()

        self.assertEqual(tasks.ready(), True)
        self.assertEqual(tasks.successful(), True)

        self.check_if_the_items_have_been_added_in_the_database(
            'test__api_publish__ok__empty_query.csv'
        )
        self.check_if_the_errors_have_been_added_in_the_database(expected)
