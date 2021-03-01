from time import sleep
from unittest import mock, TestCase

from pandas import read_csv, to_datetime
from pandas.testing import assert_frame_equal

from publisher import Publisher
from publisher.environment import PR_BASE_DIR
from publisher.model import PostgreSQLCatalogTestConnection, PostgreSQLPublisherConnection


db = PostgreSQLCatalogTestConnection()
db_publisher = PostgreSQLPublisherConnection()

celery_async = ('publisher.workers.celery_config.task_always_eager', False)

test_delay_secs = 0.6


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


@mock.patch(*celery_async)
class AsyncPublisherOkTestCase(BaseTestCases.BaseTestCase):

    @staticmethod
    def __create_and_execute_publisher(query):
        # create Publisher object and run the main method
        publisher_app = Publisher(PR_BASE_DIR, False, None, query=query)
        publisher_app.main()

        # wait N seconds to the task save the data in the database
        # before checking if the data has been inserted correctly
        sleep(test_delay_secs)

    # CBERS2B

    def test__publisher__ok__cbers2b(self):
        query = {
            'satellite': 'CBERS2B'
        }

        expected = [
            {
                'message': 'There is metadata to the `CBERS2B_XYZ_L2_DN` collection, however this collection does not exist in the database.',
                'metadata': {'collection': 'CBERS2B_XYZ_L2_DN'},
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
            }
        ]

        AsyncPublisherOkTestCase.__create_and_execute_publisher(query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers2b/test__api_publish__ok__cbers2b.csv'
        )
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    def test__publisher__ok__cbers2b_ccd_l2_dn__quicklook_does_not_exist(self):
        # CBERS2B/2007_09/CBERS2B_CCD_20070925.145654/181_096_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'CBeRS2B',
            'sensor': 'CCd',
            'start_date': '2007-09-25',
            'end_date': '2007-09-25',
            'path': 181,
            'row': '096',
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        expected = [{
            'type': 'warning',
            'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
            'metadata': {
                'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_CCD_20070925.145654/181_096_0/2_BC_UTM_WGS84'
            }
        }]

        AsyncPublisherOkTestCase.__create_and_execute_publisher(query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # CBERS4A

    def test__publisher__ok__cbers4a(self):
        query = {
            'satellite': 'CBERS4A'
        }

        expected = [
            {
                'message': 'There is NOT a DN XML file in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4A/2019_12/CBERS_4A_MUX_RAW_2019_12_28.14_15_00/221_108_0/4_BC_UTM_WGS84'},
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

        AsyncPublisherOkTestCase.__create_and_execute_publisher(query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test__api_publish__ok__cbers4a.csv'
        )
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    def test__publisher__ok__cbers4a_mux_l4_dn_or_sr__dn_file_does_not_exist(self):
        # CBERS4A/2019_12/CBERS_4A_MUX_RAW_2019_12_28.14_15_00/221_108_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'cBERs4A',
            'sensor': 'mux',
            'start_date': '2019-12-28',
            'end_date': '2019-12-28',
            'path': 221,
            'row': 108,
            'geo_processing': 4
        }

        expected = [{
            'type': 'warning',
            'message': 'There is NOT a DN XML file in this folder, then it will be ignored.',
            'metadata': {
                'folder': '/TIFF/CBERS4A/2019_12/CBERS_4A_MUX_RAW_2019_12_28.14_15_00/221_108_0/4_BC_UTM_WGS84'
            }
        }]

        AsyncPublisherOkTestCase.__create_and_execute_publisher(query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # LANDSAT1

    def test__publisher__ok__landsat1(self):
        query = {
            'satellite': 'LANDSAT1'
        }

        expected = [
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT1/1976_10/LANDSAT1_MSS_19761002.120000/010_057_0/2_BC_UTM_WGS84'},
                'type': 'warning'
            }
        ]

        AsyncPublisherOkTestCase.__create_and_execute_publisher(query)

        self.check_if_the_items_have_been_added_in_the_database(
            'landsat/test__api_publish__ok__landsat1.csv'
        )
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # LANDSAT7

    def test__publisher__ok__landsat7(self):
        query = {
            'satellite': 'LANDSAT7'
        }

        expected = [
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990719.124008/217_064_0/2_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT7/2003_06/LANDSAT7_ETM_20030601.125322/220_061_0/2_BC_UTM_WGS84'},
                'type': 'warning'
            }
        ]

        AsyncPublisherOkTestCase.__create_and_execute_publisher(query)

        self.check_if_the_items_have_been_added_in_the_database(
            'landsat/test__api_publish__ok__landsat7.csv'
        )
        self.check_if_the_errors_have_been_added_in_the_database(expected)

