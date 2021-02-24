from json import loads
from unittest import TestCase

from pandas import read_csv, to_datetime
from pandas.testing import assert_frame_equal

from publisher import create_app
from publisher.environment import FLASK_TESTING
from publisher.model import PostgreSQLCatalogTestConnection, PostgreSQLPublisherConnection


app = create_app({'TESTING': FLASK_TESTING})

# initialize the databases just one time
db = PostgreSQLCatalogTestConnection()
db.init_db()
db_publisher = PostgreSQLPublisherConnection()
db_publisher.init_db()


def read_item_from_csv(file_name):
    expected = read_csv(f'tests/publisher/{file_name}')

    expected['start_date'] = to_datetime(expected['start_date'])
    expected['end_date'] = to_datetime(expected['end_date'])
    expected['assets'] = expected['assets'].astype('str')
    expected['metadata'] = expected['metadata'].astype('str')

    return expected


class BaseTestCases:
    class BaseTestCase(TestCase):

        @classmethod
        def setUpClass(cls):
            cls.api = app.test_client()

        def setUp(self):
            # clean tables before each test case
            db.delete_from_items()
            db_publisher.delete_from_task_error()

        def get(self, url='/publish', query_string=None, expected='/publish has been executed',
                expected_status_code=200):
            response = self.api.get(url, query_string=query_string)

            self.assertEqual(expected_status_code, response.status_code)
            self.assertEqual(expected, response.get_data(as_text=True))

        def check_if_the_items_have_been_added_in_the_database(self, expected_file_path):
            # get the result from database
            result = db.select_from_items()
            # get the expected result
            expected = read_item_from_csv(expected_file_path)
            assert_frame_equal(expected, result)

        def check_if_the_items_table_is_empty(self):
            # check if the result size is equals to 0
            self.assertEqual(0, len(db.select_from_items().index))

        def check_if_the_errors_have_been_added_in_the_database(self, expected):
            # get the result from database
            result = db_publisher.select_from_task_error()
            self.assertEqual(expected, result)


class PublisherPublishOkTestCase(BaseTestCases.BaseTestCase):

    def test_publish__ok__empty_query(self):
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

        self.get()

        self.check_if_the_items_have_been_added_in_the_database(
            'test_publish__ok__empty_query.csv'
        )
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    def test_publish__ok__l4_dn__missing_satellite_and_sensor(self):
        # CBERS4A/2019_12/CBERS_4A_WFI_RAW_2019_12_27.13_53_00_ETC2/215_132_0/4_BC_UTM_WGS84
        query = {
            'start_date': '2019-12-01',
            'end_date': '2020-06-30',
            'path': '215',
            'row': '132',
            'geo_processing': '4',
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'test_publish__ok__l4_dn__missing_satellite_and_sensor.csv'
        )


class PublisherPublishCbers2BOkTestCase(BaseTestCases.BaseTestCase):

    # CBERS2B CCD

    def test_publish__ok__cbers2b_ccd_l2_dn(self):
        # CBERS2B/2010_03/CBERS2B_CCD_20100301.130915/151_098_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS2b',
            'sensor': 'CcD',
            'start_date': '2010-03-01',
            'end_date': '2010-03-15',
            'path': 151,
            'row': 98,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers2b/test_publish__ok__cbers2b_ccd_l2_dn.csv'
        )

    def test_publish__ok__cbers2b_ccd_l2_dn__quicklook_does_not_exist(self):
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

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # CBERS2B HRC

    def test_publish__ok__cbers2b_hrc_l2_dn__path_151_row_141(self):
        # CBERS2B/2010_03/CBERS2B_HRC_20100301.130915/151_B_141_5_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS2b',
            'sensor': 'hRC',
            'start_date': '2010-03-01',
            'end_date': '2010-03-02',
            'path': 151,
            'row': 141,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers2b/test_publish__ok__cbers2b_hrc_l2_dn__path_151_row_141.csv'
        )

    def test_publish__ok__cbers2b_hrc_l2_dn__path_151_row_142(self):
        # CBERS2B/2010_03/CBERS2B_HRC_20100301.130915/151_A_142_1_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS2b',
            'sensor': 'hRC',
            'start_date': '2010-03-01',
            'end_date': '2010-03-02',
            'path': 151,
            'row': 142,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers2b/test_publish__ok__cbers2b_hrc_l2_dn__path_151_row_142.csv'
        )

    def test_publish__ok__cbers2b_hrc_l2_dn__quicklook_does_not_exist(self):
        # CBERS2B/2007_09/CBERS2B_HRC_20070929.124300/145_C_111_3_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS2b',
            'sensor': 'HrC',
            'start_date': '2007-09-01',
            'end_date': '2007-09-30',
            'path': 145,
            'row': 111,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        expected = [{
            'type': 'warning',
            'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
            'metadata': {
                'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_HRC_20070929.124300/145_C_111_3_0/2_BC_UTM_WGS84'
            }
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # CBERS2B WFI

    def test_publish__ok__cbers2b_wfi_l2_dn(self):
        # CBERS2B/2010_03/CBERS2B_WFI_20100301.144734/177_092_0/2_BC_LCC_WGS84
        query = {
            'satellite': 'CBERS2b',
            'sensor': 'wFI',
            'start_date': '2010-02-28',
            'end_date': '2010-03-01',
            'path': 177,
            'row': '092',
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers2b/test_publish__ok__cbers2b_wfi_l2_dn.csv'
        )

    def test_publish__ok__cbers2b_wfi_l2_dn__quicklook_does_not_exist(self):
        # CBERS2B/2007_09/CBERS2B_WFI_20070928.131338/154_124_0/2_BC_LCC_WGS84
        query = {
            'satellite': 'CBERS2b',
            'sensor': 'wFI',
            'start_date': '2007-09-28',
            'end_date': '2007-09-28',
            'path': '154',
            'row': 124,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        expected = [{
            'type': 'warning',
            'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
            'metadata': {
                'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_WFI_20070928.131338/154_124_0/2_BC_LCC_WGS84'
            }
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # CBERS2B XYZ

    def test_publish__ok__cbers2b_xyz_l2_dn__collection_does_not_exist(self):
        # CBERS2B/2007_09/CBERS2B_XYZ_20070925.145654/181_096_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS2B',
            'sensor': 'XYZ', # <-- sensor does not exist
            'start_date': '2007-09-01',
            'end_date': '2007-09-30',
            'path': 181,
            'row': 96,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        expected = [{
            'type': 'warning',
            'message': ('There is metadata to the `CBERS2B_XYZ_L2_DN` collection, however '
                        'this collection does not exist in the database.'),
            'metadata': {
                'collection': 'CBERS2B_XYZ_L2_DN'
            }
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)


class PublisherPublishCbers4OkTestCase(BaseTestCases.BaseTestCase):

    # CBERS4 AWFI (DN and SR)

    def test_publish__ok__cbers4_awfi_l4_dn__dn_tiff_file_does_not_exist(self):
        # CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_135_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CBErS4',
            'sensor': 'AwFi',
            'start_date': '2020-12-28',
            'end_date': '2020-12-28',
            'path': '157',
            'row': 135,
            'geo_processing': 4,
            'radio_processing': 'Dn'
        }

        expected = [{
            'message': ('There is NOT a TIFF file in this folder that ends with the '
                        '`BAND13.tif` template, then it will be ignored.'),
            'metadata': {
                'folder': '/TIFF/CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_135_0/4_BC_UTM_WGS84'
            },
            'type': 'warning'
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    def test_publish__ok__cbers4_awfi_l4_sr(self):
        # CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_135_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS4',
            'sensor': 'aWfI',
            'start_date': '2020-12-28',
            'end_date': '2020-12-28',
            'path': '157',
            'row': 135,
            'geo_processing': 4,
            'radio_processing': 'sR'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4/test_publish__ok__cbers4_awfi_l4_sr.csv'
        )

    def test_publish__ok__cbers4_awfi_l4_dn_and_sr__dn_tiff_file_does_not_exist(self):
        # CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_135_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'cBERs4',
            'sensor': 'AWFI',
            'start_date': '2020-12-28',
            'end_date': '2020-12-28',
            'path': '157',
            'row': 135,
            'geo_processing': 4,
            # ommit `radio_processing` to return both `DN` and `SR`
        }

        expected = [{
            'message': ('There is NOT a TIFF file in this folder that ends with the '
                        '`BAND13.tif` template, then it will be ignored.'),
            'metadata': {
                'folder': '/TIFF/CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_135_0/4_BC_UTM_WGS84'
            },
            'type': 'warning'
        }]

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4/test_publish__ok__cbers4_awfi_l4_dn_and_sr__dn_tiff_file_does_not_exist.csv'
        )
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    def test_publish__ok__cbers4_awfi__path_row_folder_is_empty(self):
        # CBERS4/2015_01/CBERS_4_AWFI_DRD_2015_01_16.13_39_12_CB11/161_093_0/
        query = {
            'satellite': 'CBErS4',
            'sensor': 'AwFi',
            'start_date': '2015-01-16',
            'end_date': '2015-01-16',
            'path': '161',
            'row': '093'
        }

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()

    def test_publish__ok__cbers4_awfi_l4_dn_and_sr__evi_tiff_file_does_not_exist(self):
        # EVI file does not exist, then it is not added to assets
        # CBERS4/2021_02/CBERS_4_AWFI_DRD_2021_02_01.13_07_00_CB11/154_117_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS4',
            'sensor': 'aWfI',
            'start_date': '2021-02-01',
            'end_date': '2021-02-01',
            'path': '154',
            'row': 117,
            'geo_processing': 4,
            # omit 'radio_processing' to get both `DN` and `SR` scenes
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4/test_publish__ok__cbers4_awfi_l4_dn_and_sr__evi_tiff_file_does_not_exist.csv'
        )

    def test_publish__ok__cbers4_awfi_l4_sr__ndvi_tiff_file_does_not_exist(self):
        # NDVI file does not exist, then it is not added to assets
        # CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_136_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS4',
            'sensor': 'aWfI',
            'start_date': '2020-12-28',
            'end_date': '2020-12-28',
            'path': '157',
            'row': 136,
            'geo_processing': 4,
            'radio_processing': 'sR'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4/test_publish__ok__cbers4_awfi_l4_sr__ndvi_tiff_file_does_not_exist.csv'
        )

    def test_publish__ok__cbers4_awfi_l4_sr__quality_tiff_file_does_not_exist(self):
        # CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_135_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS4',
            'sensor': 'aWfI',
            'start_date': '2020-12-28',
            'end_date': '2020-12-28',
            'path': '157',
            'row': 137,
            'geo_processing': 4,
            'radio_processing': 'sR'
        }

        expected = [{
            'message': ('There is NOT a TIFF file in this folder that ends with the '
                        '`CMASK_GRID_SURFACE.tif` template, then it will be ignored.'),
            'metadata': {
                'folder': '/TIFF/CBERS4/2020_12/CBERS_4_AWFI_DRD_2020_12_28.13_17_30_CB11/157_137_0/4_BC_UTM_WGS84'
            },
            'type': 'warning'
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # CBERS4 MUX (DN and SR)

    def test_publish__ok__cbers4_mux_l2_dn_and_sr__dn_xml_file_does_not_exist(self):
        # CBERS4/2016_01/CBERS_4_MUX_DRD_2016_01_01.13_28_32_CB11/157_101_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'cBERs4',
            'sensor': 'MUX',
            'start_date': '2016-01-01',
            'end_date': '2016-01-01',
            'path': '157',
            'row': 101,
            'geo_processing': 2,
            # ommit `radio_processing` to return both `DN` and `SR`
        }

        expected = [{
            'type': 'warning',
            'message': 'There is NOT a DN XML file in this folder, then it will be ignored.',
            'metadata': {
                'folder': '/TIFF/CBERS4/2016_01/CBERS_4_MUX_DRD_2016_01_01.13_28_32_CB11/157_101_0/2_BC_UTM_WGS84'
            }
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    def test_publish__ok__cbers4_mux_l4_dn__dn_xml_file_does_not_exist(self):
        # CBERS4/2020_07/CBERS_4_MUX_DRD_2020_07_31.13_07_00_CB11/155_103_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CbErS4',
            'sensor': 'MuX',
            'start_date': '2020-07-30',
            'end_date': '2020-08-01',
            'path': 155,
            'row': '103',
            'geo_processing': 4,
            'radio_processing': 'dn'
        }

        expected = [{
            'type': 'warning',
            'message': 'There is NOT a DN XML file in this folder, then it will be ignored.',
            'metadata': {
                'folder': '/TIFF/CBERS4/2020_07/CBERS_4_MUX_DRD_2020_07_31.13_07_00_CB11/155_103_0/4_BC_UTM_WGS84'
            }
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    def test_publish__ok__cbers4_mux_l4_dn(self):
        # CBERS4/2018_01/CBERS_4_MUX_DRD_2018_01_01.13_14_00_CB11/156_103_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS4',
            'sensor': 'mux',
            'start_date': '2018-01-01',
            'end_date': '2018-01-01',
            'path': 156,
            'row': '103',
            'geo_processing': 4,
            'radio_processing': 'dn'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4/test_publish__ok__cbers4_mux_l4_dn.csv'
        )

    def test_publish__ok__cbers4_mux_l4_sr__evi_tiff_file_does_not_exist(self):
        # CBERS4/2018_01/CBERS_4_MUX_DRD_2018_01_01.13_14_00_CB11/156_103_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS4',
            'sensor': 'mux',
            'start_date': '2018-01-01',
            'end_date': '2018-01-01',
            'path': 156,
            'row': '103',
            'geo_processing': 4,
            'radio_processing': 'sr'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4/test_publish__ok__cbers4_mux_l4_sr__evi_tiff_file_does_not_exist.csv'
        )

    def test_publish__ok__cbers4_mux_l4_dn_and_sr__evi_tiff_file_does_not_exist(self):
        # CBERS4/2018_01/CBERS_4_MUX_DRD_2018_01_01.13_14_00_CB11/156_103_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS4',
            'sensor': 'mux',
            'start_date': '2018-01-01',
            'end_date': '2018-01-01',
            'path': 156,
            'row': '103',
            'geo_processing': 4,
            # omit 'radio_processing' to get both `DN` and `SR` scenes
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4/test_publish__ok__cbers4_mux_l4_dn_and_sr__evi_tiff_file_does_not_exist.csv'
        )

    # CBERS4 PAN5M (DN)

    # CBERS4 PAN10M (DN)

    def test_publish__ok__cbers4_pan10m_l2_sr__next_to_0h(self):
        # CBERS4/2021_02/CBERS_4_PAN10M_DRD_2021_02_02.01_32_45_CB11/073_113_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'CBErS4',
            'sensor': 'Pan10m',
            'start_date': '2021-02-01',
            'end_date': '2021-02-01',
            'path': 73,
            'row': 113,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4/test_publish__ok__cbers4_pan10m_l2_sr__next_to_0h.csv'
        )


class PublisherPublishCbers4AOkTestCase(BaseTestCases.BaseTestCase):

    # CBERS4A MUX

    def test_publish__ok__cbers4a_mux_l2_dn(self):
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'MUx',
            'start_date': '2021-01-01',
            'end_date': '2021-01-01',
            'path': 209,
            'row': 105,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test_publish__ok__cbers4a_mux_l2_dn.csv'
        )

    def test_publish__ok__cbers4a_mux_l2_dn__next_to_0h(self):
        # scene_dir with time between 0h and 5h, consider one day ago
        # CBERS4A/2020_04/CBERS_4A_MUX_RAW_2020_04_06.00_56_20_CP5/164_025_0/
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'MUX',
            'start_date': '2020-04-05',
            'end_date': '2020-04-05',
            'path': 164,
            'row': 25,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test_publish__ok__cbers4a_mux_l2_dn__next_to_0h.csv'
        )

    def test_publish__ok__cbers4a_mux_l4_dn(self):
        # CBERS4A/2019_12/CBERS_4A_MUX_RAW_2019_12_27.13_53_00_ETC2/215_150_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'MUx',
            'start_date': '2019-12-27',
            'end_date': '2019-12-27',
            'path': 215,
            'row': 150,
            'geo_processing': 4,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test_publish__ok__cbers4a_mux_l4_dn.csv'
        )

    def test_publish__ok__cbers4a_mux_l4_dn__empty_folder(self):
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'MUx',
            'start_date': '2021-01-01',
            'end_date': '2021-01-01',
            'path': 209,
            'row': 105,
            'geo_processing': 4, # <-- there is not this geometric processing
            'radio_processing': 'DN'
        }

        expected = [{
            'message': 'This folder is valid, but it is empty.',
            'metadata': {
                'folder': '/TIFF/CBERS4A/2021_01/CBERS_4A_MUX_RAW_2021_01_01.13_48_30_ETC2/209_105_0/4_BC_UTM_WGS84'
            },
            'type': 'warning'
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    def test_publish__ok__cbers4a_mux_l4_dn_or_sr__dn_file_does_not_exist(self):
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

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # CBERS4A WFI

    def test_publish__ok__cbers4a_wfi_l2_and_l4_sr(self):
        # CBERS4A/2020_12/CBERS_4A_WFI_RAW_2020_12_07.14_03_00_ETC2/214_108_0/4_BC_UTM_WGS84/
        query = {
            'satellite': 'cbers4a',
            'sensor': 'wfi',
            'start_date': '2020-12-07',
            'end_date': '2020-12-07',
            'path': '214',
            'row': '108',
            # 'geo_processing' is empty in order to publish both `L2` and `L4` files, if they exist
            'radio_processing': 'SR'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test_publish__ok__cbers4a_wfi_l2_and_l4_sr.csv'
        )

    def test_publish__ok__cbers4a_wfi_l4_dn(self):
        # CBERS4A/2019_12/CBERS_4A_WFI_RAW_2019_12_27.13_53_00_ETC2/215_132_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'wfi',
            'start_date': '2019-12-20',
            'end_date': '2019-12-30',
            'path': '215',
            'row': '132',
            'geo_processing': '4',
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test_publish__ok__cbers4a_wfi_l4_dn.csv'
        )

    def test_publish__ok__cbers4a_wfi_l4_sr(self):
        # CBERS4A/2020_12/CBERS_4A_WFI_RAW_2020_12_07.14_03_00_ETC2/214_108_0/4_BC_UTM_WGS84/
        query = {
            'satellite': 'cbers4a',
            'sensor': 'wfi',
            'start_date': '2020-12-07',
            'end_date': '2020-12-07',
            'path': '214',
            'row': '108',
            'geo_processing': '4',
            'radio_processing': 'sr'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test_publish__ok__cbers4a_wfi_l4_sr.csv'
        )

    def test_publish__ok__cbers4a_wfi_l4_dn_and_sr(self):
        # CBERS4A/2020_12/CBERS_4A_WFI_RAW_2020_12_07.14_03_00_ETC2/214_108_0/4_BC_UTM_WGS84/
        query = {
            'satellite': 'cbers4a',
            'sensor': 'wfi',
            'start_date': '2020-12-07',
            'end_date': '2020-12-07',
            'path': '214',
            'row': '108',
            'geo_processing': '4'
            # radio processing is empty in order to publish both `DN` and `SR` files
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test_publish__ok__cbers4a_wfi_l4_dn_and_sr.csv'
        )

    def test_publish__ok__cbers4a_wfi__empty_result(self):
        # CBERS4A/2020_11/CBERS_4A_WFI_RAW_2020_11_10.13_41_00_ETC2/207_?_0/2_BC_UTM_WGS84
        # `207_148_0` exist, but `207_105_0` does not exist
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'wfi',
            'start_date': '2020-11-10',
            'end_date': '2020-11-10',
            'path': '207',
            'row': '105', # <-- there is not this row
            'geo_processing': '2',
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()

    def test_publish__ok__cbers4a_wfi__missing_geo_and_radio_processings(self):
        # CBERS4A/2019_12/CBERS_4A_WFI_RAW_2019_12_27.13_53_00_ETC2/215_132_0/4_BC_UTM_WGS84
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'wfi',
            'start_date': '2019-12-01',
            'end_date': '2020-06-30',
            'path': '215',
            'row': '132'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test_publish__ok__cbers4a_wfi__missing_geo_and_radio_processings.csv'
        )

    def test_publish__ok__cbers4a_wfi__missing_path_and_row(self):
        # CBERS4A/2019_12/CBERS_4A_WFI_RAW_2019_12_27.13_53_00_ETC2/215_132_0/4_BC_UTM_WGS84/
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'wfi',
            'start_date': '2019-12-01',
            'end_date': '2020-06-30',
            'geo_processing': '4',
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test_publish__ok__cbers4a_wfi__missing_path_and_row.csv'
        )

    # CBERS4A WPM

    def test_publish__ok__cbers4a_wpm_l2_dn(self):
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'wPm',
            'start_date': '2020-04-01',
            'end_date': '2020-04-30',
            'path': '202',
            'row': 112,
            'geo_processing': '2',
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test_publish__ok__cbers4a_wpm_l2_dn.csv'
        )

    def test_publish__ok__cbers4a_wpm_l2_dn__next_to_5h(self):
        # scene_dir with time between 0h and 5h, consider one day ago
        # CBERS4A/2020_08/CBERS_4A_WPM_RAW_2020_08_17.03_52_45_ETC2/373_019_0/
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'WpM',
            'start_date': '2020-08-16',
            'end_date': '2020-08-16',
            'path': '373',
            'row': '019',
            'geo_processing': '2',
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'cbers4a/test_publish__ok__cbers4a_wpm_l2_dn__next_to_5h.csv'
        )

    def test_publish__ok__cbers4a_wpm__empty_result(self):
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'wPm',
            'start_date': '2020-05-01', # <-- there is not this range date
            'end_date': '2020-05-30',
            'path': '202',
            'row': 112,
            'geo_processing': '2',
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()


class PublisherPublishLandsatOkTestCase(BaseTestCases.BaseTestCase):

    # LANDSAT1 MSS

    def test_publish__ok__landsat1_mss_l2_dn(self):
        # LANDSAT1/1973_05/LANDSAT1_MSS_19730521.120000/237_059_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'LANDsat1',
            'sensor': 'MSs',
            'start_date': '1973-05-20',
            'end_date': '1973-05-21',
            'path': 237,
            'row': '059',
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'landsat/test_publish__ok__landsat1_mss_l2_dn.csv'
        )

    def test_publish__ok__landsat1_mss_l2_dn__quicklook_does_not_exist(self):
        # LANDSAT1/1976_10/LANDSAT1_MSS_19761002.120000/010_057_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'lanDSAT1',
            'sensor': 'mss',
            'start_date': '1976-10-02',
            'end_date': '1976-10-02',
            'path': 10,
            'row': '057',
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        expected = [{
            'type': 'warning',
            'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
            'metadata': {
                'folder': '/TIFF/LANDSAT1/1976_10/LANDSAT1_MSS_19761002.120000/010_057_0/2_BC_UTM_WGS84'
            }
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # LANDSAT2 MSS

    def test_publish__ok__landsat2_mss_l2_dn(self):
        # LANDSAT2/1982_02/LANDSAT2_MSS_19820201.120000/005_055_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'lANDSAT2',
            'sensor': 'mSS',
            'start_date': '1982-02-01',
            'end_date': '1982-02-01',
            'path': 5,
            'row': 55,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'landsat/test_publish__ok__landsat2_mss_l2_dn.csv'
        )

    def test_publish__ok__landsat2_mss_l2_dn__quicklook_does_not_exist(self):
        # LANDSAT2/1975_07/LANDSAT2_MSS_19750724.123000/230_070_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'LANdSAt2',
            'sensor': 'MsS',
            'start_date': '1975-07-24',
            'end_date': '1975-07-25',
            'path': 230,
            'row': '070',
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        expected = [{
            'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
            'metadata': {
                'folder': '/TIFF/LANDSAT2/1975_07/LANDSAT2_MSS_19750724.123000/230_070_0/2_BC_UTM_WGS84'
            },
            'type': 'warning'
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # LANDSAT3 MSS

    def test_publish__ok__landsat3_mss_l2_dn(self):
        # LANDSAT3/1978_04/LANDSAT3_MSS_19780405.120000/235_075_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'LAndSAT3',
            'sensor': 'MsS',
            'start_date': '1978-04-05',
            'end_date': '1978-04-05',
            'path': 235,
            'row': '075',
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'landsat/test_publish__ok__landsat3_mss_l2_dn.csv'
        )

    def test_publish__ok__landsat3_mss_l2_dn__quicklook_does_not_exist(self):
        # LANDSAT3/1982_08/LANDSAT3_MSS_19820802.120000/231_072_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'laNDSAT3',
            'sensor': 'MSs',
            'start_date': '1982-08-02',
            'end_date': '1982-08-02',
            'path': '231',
            'row': 72,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        expected = [{
            'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
            'metadata': {
                'folder': '/TIFF/LANDSAT3/1982_08/LANDSAT3_MSS_19820802.120000/231_072_0/2_BC_UTM_WGS84'
            },
            'type': 'warning'
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # LANDSAT5 TM

    def test_publish__ok__landsat5_tm_l2_dn(self):
        # LANDSAT5/2011_11/LANDSAT5_TM_20111101.140950/233_054_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'LAndSAT5',
            'sensor': 'TM',
            'start_date': '2011-11-01',
            'end_date': '2011-11-02',
            'path': 233,
            'row': 54,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'landsat/test_publish__ok__landsat5_tm_l2_dn.csv'
        )

    def test_publish__ok__landsat5_tm_l2_dn__quicklook_does_not_exist(self):
        # LANDSAT5/1984_04/LANDSAT5_TM_19840406.124930/223_062_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'laNDSAT5',
            'sensor': 'tm',
            'start_date': '1984-04-05',
            'end_date': '1984-04-06',
            'path': 223,
            'row': '062',
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        expected = [{
            'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
            'metadata': {
                'folder': '/TIFF/LANDSAT5/1984_04/LANDSAT5_TM_19840406.124930/223_062_0/2_BC_UTM_WGS84'
            },
            'type': 'warning'
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)

    # LANDSAT7 ETM

    def test_publish__ok__landsat7_etm_l2_dn(self):
        # LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'LAndSAT7',
            'sensor': 'EtM',
            'start_date': '1999-07-31',
            'end_date': '1999-07-31',
            'path': 4,
            'row': 72,
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        self.get(query_string=query)

        self.check_if_the_items_have_been_added_in_the_database(
            'landsat/test_publish__ok__landsat7_etm_l2_dn.csv'
        )

    def test_publish__ok__landsat7_etm_l2_dn__quicklook_does_not_exist(self):
        # LANDSAT7/1999_07/LANDSAT7_ETM_19990719.124008/217_064_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'laNDSAT7',
            'sensor': 'ETm',
            'start_date': '1999-07-19',
            'end_date': '1999-07-19',
            'path': '217',
            'row': '064',
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        expected = [{
            'type': 'warning',
            'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
            'metadata': {
                'folder': '/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990719.124008/217_064_0/2_BC_UTM_WGS84'
            }
        }]

        self.get(query_string=query)

        self.check_if_the_items_table_is_empty()
        self.check_if_the_errors_have_been_added_in_the_database(expected)


class PublisherPublishErrorTestCase(BaseTestCases.BaseTestCase):

    def test_publish__error__invalid_values(self):
        query = {
            'satellite': 'CIBYRS4A',
            'sensor': 'wPm',
            'start_date': '2020-15-31',
            'end_date': '2020-05',
            'path': '0',
            'row': 1000,
            'geo_processing': '5',
            'radio_processing': 'Dz'
        }

        expected = {
            'code': 400,
            'name': 'Bad Request',
            'description': {
                'satellite': ["value does not match regex '^CBERS[1-4][A-B]*|^LANDSAT\\d\'"],
                'start_date': [
                    "field 'start_date' cannot be coerced: time data '2020-15-31' does not match format '%Y-%m-%d'",
                    'must be of datetime type'
                ],
                'end_date': [
                    "field 'end_date' cannot be coerced: time data '2020-05' does not match format '%Y-%m-%d'",
                    'must be of datetime type'
                ],
                'path': ['min value is 1'],
                'row': ['max value is 999'],
                'geo_processing': ['max value is 4'],
                'radio_processing': ['unallowed value DZ']
            }
        }

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(400, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        self.check_if_the_items_table_is_empty()

    def test_publish__error__unknown_fields(self):
        query = {
            'satelliti': 'CBERS4A',
            'sensors': 'wfi',
            'date': '2019-12-01',
            'pathy': '215',
            'rown': '132',
            'processing': '4'
        }

        expected = {
            'code': 400,
            'name': 'Bad Request',
            'description': {
                'satelliti': ['unknown field'],
                'sensors': ['unknown field'],
                'date': ['unknown field'],
                'pathy': ['unknown field'],
                'rown': ['unknown field'],
                'processing': ['unknown field']
            }
        }

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(400, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        self.check_if_the_items_table_is_empty()
