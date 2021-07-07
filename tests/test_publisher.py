from time import sleep
from unittest import mock

from publisher import Publisher, DBFactory, PR_BASE_DIR

from tests.base import BaseTestCases, celery_async, test_delay_secs


# create a db connection based on the environment variable
db_connection = DBFactory.factory()
# get all available collections and tiles from the database
df_collections = db_connection.select_from_collections()
df_tiles = db_connection.select_from_tiles()


@mock.patch(*celery_async)
class AsyncPublisherOkTestCase(BaseTestCases.BaseTestCase):

    @staticmethod
    def _create_and_execute_publisher(query):
        # create Publisher object and run the main method
        publisher_app = Publisher(PR_BASE_DIR, df_collections, df_tiles, query=query)
        publisher_app.main()

        # wait N seconds to the task save the data in the database
        # before checking if the data has been inserted correctly
        sleep(test_delay_secs)

    # AMAZONIA1

    def test__publisher__ok__amazonia1(self):
        query = {
            'satellite': 'AMAZONIA1',
            'start_date': '1950-01-01',
            'end_date': '2050-12-31'
        }

        expected = [
            {
                'message': 'Path/row directory cannot be decoded: `invalid_folder`.',
                'metadata': {
                    'folder': '/TIFF/AMAZONIA1/2021_03/AMAZONIA_1_WFI_DRD_2021_03_03.12_57_40_CB11',
                    'method': 'check_path_row_dir'
                },
                'type': 'error'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/AMAZONIA1/2021_03/AMAZONIA_1_WFI_DRD_2021_03_03.12_57_40_CB11/217_015_0/4_BC_LCC_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/AMAZONIA1/2021_03/AMAZONIA_1_WFI_DRD_2021_03_03.14_35_23_CB11_SIR18/233_017_0/4_BC_LCC_WGS84'},
                'type': 'warning'
            }
        ]

        AsyncPublisherOkTestCase._create_and_execute_publisher(query)

        self.check_if_the_items_have_been_added_in_the_database(
            'amazonia1/test__api_publish__ok__amazonia1.csv'
        )
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # CBERS2B

    def test__publisher__ok__cbers2b(self):
        query = {
            'satellite': 'CBERS2B',
            'start_date': '1950-01-01',
            'end_date': '2050-12-31'
        }

        expected = [
            {
                'message': 'There is metadata to the `CBERS2B_XYZ_L2_DN` collection, however this collection does not exist in the database.',
                'metadata': {'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_XYZ_20070925.145654/181_096_0/2_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_CCD_20070925.145654/181_096_0/2_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_HRC_20070929.124300/145_C_111_3_0/2_BC_UTM_WGS84'},
                'type': 'error',
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_WFI_20070928.131338/154_124_0/2_BC_LCC_WGS84'},
                'type': 'error'
            }
        ]

        AsyncPublisherOkTestCase._create_and_execute_publisher(query)

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
            'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
            'metadata': {'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_CCD_20070925.145654/181_096_0/2_BC_UTM_WGS84'},
            'type': 'error'
        }]

        AsyncPublisherOkTestCase._create_and_execute_publisher(query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # CBERS4

    def test__publisher__ok__cbers4(self):
        query = {
            'satellite': 'CBERS4',
            'start_date': '1950-01-01',
            'end_date': '2050-12-31'
        }

        expected = [
            {
                'message': 'There is NOT a TIFF file in this folder that ends with the `BAND13.tif` template, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_135_0/4_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'There is NOT a TIFF file in this folder that ends with the `BAND13.tif` template, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_136_0/4_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'There is NOT a TIFF file in this folder that ends with the `BAND13.tif` template, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_137_0/4_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'There is NOT a TIFF file in this folder that ends with the `BAND5.tif` template, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2016_01/CBERS_4_MUX_DRD_2016_01_01.13_28_32_CB11/157_101_0/2_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'There is NOT a TIFF file in this folder that ends with the `BAND5.tif` template, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2020_07/CBERS_4_MUX_DRD_2020_07_31.13_07_00_CB11/155_103_0/4_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'There is NOT a TIFF file in this folder that ends with the `CMASK_GRID_SURFACE.tif` template, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_137_0/4_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4/2021_02/CBERS_4_PAN10M_DRD_2021_02_02.01_32_45_CB11/073_113_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            }
        ]

        AsyncPublisherOkTestCase._create_and_execute_publisher(query)

        self.check_if_the_errors_have_been_added_in_the_database(expected)
        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4/test__api_publish__ok__cbers4.csv'
        )

    # CBERS4A

    def test__publisher__ok__cbers4a(self):
        query = {
            'satellite': 'CBERS4A',
            'start_date': '1950-01-01',
            'end_date': '2050-12-31'
        }

        expected = [
            {
                'message': 'There is NOT a L4 JSON file (i.e. `*h5_*.json`) in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4A/2021_06/CBERS_4A_WFI_RAW_2021_06_15.13_45_00_ETC2/207_132_0/4_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4A/2019_12/CBERS_4A_MUX_RAW_2019_12_28.14_15_00/221_108_0/4_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4A/2020_12/CBERS_4A_WFI_RAW_2020_12_22.13_53_30_ETC2_CHUNK/211_108_0/4_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4A/2020_04/CBERS_4A_MUX_RAW_2020_04_06.00_56_20_CP5/164_025_0/4_BC_UTM_WGS84'},
                'type': 'warning'
            },
            {
                'message': 'This folder is valid, but it is empty.',
                'metadata': {'folder': '/TIFF/CBERS4A/2020_04/CBERS_4A_MUX_RAW_2020_04_23.01_24_22_CP5/266_023_0/4_BC_UTM_WGS84'},
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

        AsyncPublisherOkTestCase._create_and_execute_publisher(query)

        self.check_if_the_errors_have_been_added_in_the_database(expected)
        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test__api_publish__ok__cbers4a.csv'
        )

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
            'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
            'metadata': {'folder': '/TIFF/CBERS4A/2019_12/CBERS_4A_MUX_RAW_2019_12_28.14_15_00/221_108_0/4_BC_UTM_WGS84'},
            'type': 'error'
        }]

        AsyncPublisherOkTestCase._create_and_execute_publisher(query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # LANDSAT1

    def test__publisher__ok__landsat1(self):
        query = {
            'satellite': 'LANDSAT1',
            'start_date': '1950-01-01',
            'end_date': '2050-12-31'
        }

        expected = [
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT1/1976_10/LANDSAT1_MSS_19761002.120000/010_057_0/2_BC_UTM_WGS84'},
                'type': 'error'
            }
        ]

        AsyncPublisherOkTestCase._create_and_execute_publisher(query)

        self.check_if_the_items_have_been_added_in_the_database(
            'landsat/test__api_publish__ok__landsat1.csv'
        )
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # LANDSAT7

    def test__publisher__ok__landsat7(self):
        query = {
            'satellite': 'LANDSAT7',
            'start_date': '1950-01-01',
            'end_date': '2050-12-31'
        }

        expected = [
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990719.124008/217_064_0/2_BC_UTM_WGS84'},
                'type': 'error'
            },
            {
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT7/2003_06/LANDSAT7_ETM_20030601.125322/220_061_0/2_BC_UTM_WGS84'},
                'type': 'error'
            }
        ]

        AsyncPublisherOkTestCase._create_and_execute_publisher(query)

        self.check_if_the_items_have_been_added_in_the_database(
            'landsat/test__api_publish__ok__landsat7.csv'
        )
        self.check_if_the_errors_have_been_added_in_the_database(expected)
