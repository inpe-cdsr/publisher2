from json import loads
from unittest import TestCase

from pandas import DataFrame, read_csv, to_datetime
from pandas.testing import assert_frame_equal

from publisher import create_app
from publisher.model import PostgreSQLTestConnection


test_config={'TESTING': True}
# recreate the test database just one time
app = create_app(test_config)


def read_item_from_csv(file_name):
    expected = read_csv(f'tests/publisher/{file_name}')

    expected['start_date'] = to_datetime(expected['start_date'])
    expected['end_date'] = to_datetime(expected['end_date'])
    expected['assets'] = expected['assets'].astype('str')
    expected['metadata'] = expected['metadata'].astype('str')

    return expected


class PublisherPublishOkTestCase(TestCase):

    @classmethod
    def setUpClass(cls):
        cls.api = app.test_client()
        cls.db = PostgreSQLTestConnection()

    def setUp(self):
        # clean table before testing
        self.db.delete_from_items()

    def test_publish__ok__empty_query(self):
        expected = [
            {
                'type': 'warning',
                'message': ('There is metadata to the `CBERS2B_XYZ_L2_DN` collection, however this '
                            'collection does not exist in the database.'),
                'metadata': {'collection': 'CBERS2B_XYZ_L2_DN'}
            },
            {
                'type': 'warning',
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/LANDSAT1/1976_10/LANDSAT1_MSS_19761002.120000/010_057_0/2_BC_UTM_WGS84'}
            },
            {
                'type': 'warning',
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_WFI_20070928.131338/154_124_0/2_BC_LCC_WGS84'}
            },
            {
                'type': 'warning',
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_HRC_20070929.124300/145_C_111_3_0/2_BC_UTM_WGS84'}
            },
            {
                'type': 'warning',
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_CCD_20070925.145654/181_096_0/2_BC_UTM_WGS84'}
            },
            {
                'type': 'warning',
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {'folder': '/TIFF/CBERS4A/2019_12/CBERS_4A_MUX_RAW_2019_12_28.14_15_00/221_108_0/4_BC_UTM_WGS84'}
            }
        ]

        response = self.api.get('/publish')

        self.assertEqual(200, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        # check if the items have been added in the database
        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__empty_query.csv')

        assert_frame_equal(expected, result)


class PublisherPublishCbers2BOkTestCase(TestCase):

    @classmethod
    def setUpClass(cls):
        cls.api = app.test_client()
        cls.db = PostgreSQLTestConnection()

    def setUp(self):
        # clean table before testing
        self.db.delete_from_items()

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers2b_ccd_l2_dn.csv')

        assert_frame_equal(expected, result)

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

        expected = [
            {
                'type': 'warning',
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {
                    'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_CCD_20070925.145654/181_096_0/2_BC_UTM_WGS84'
                }
            }
        ]

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull'])  # empty dataframe

        assert_frame_equal(expected, result)

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers2b_hrc_l2_dn__path_151_row_141.csv')

        assert_frame_equal(expected, result)

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers2b_hrc_l2_dn__path_151_row_142.csv')

        assert_frame_equal(expected, result)

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

        expected = [
            {
                'type': 'warning',
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {
                    'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_HRC_20070929.124300/145_C_111_3_0/2_BC_UTM_WGS84'
                }
            }
        ]

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull'])  # empty dataframe

        assert_frame_equal(expected, result)

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers2b_wfi_l2_dn.csv')

        assert_frame_equal(expected, result)

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

        expected = [
            {
                'type': 'warning',
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {
                    'folder': '/TIFF/CBERS2B/2007_09/CBERS2B_WFI_20070928.131338/154_124_0/2_BC_LCC_WGS84'
                }
            }
        ]

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull'])  # empty dataframe

        assert_frame_equal(expected, result)

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

        response = self.api.get('/publish', query_string=query)
        expected = [{
            'type': 'warning',
            'metadata': {
                'collection': 'CBERS2B_XYZ_L2_DN'
            },
            'message': ('There is metadata to the `CBERS2B_XYZ_L2_DN` collection, however '
                        'this collection does not exist in the database.')
        }]

        self.assertEqual(200, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull'])  # empty dataframe

        assert_frame_equal(expected, result)


class PublisherPublishCbers4AOkTestCase(TestCase):

    @classmethod
    def setUpClass(cls):
        cls.api = app.test_client()
        cls.db = PostgreSQLTestConnection()

    def setUp(self):
        # clean table before testing
        self.db.delete_from_items()

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers4a_mux_l2_dn.csv')

        assert_frame_equal(expected, result)

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers4a_mux_l2_dn__next_to_0h.csv')

        assert_frame_equal(expected, result)

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items('test_publish__ok__cbers4a_mux_l4_dn.csv')
        expected = read_item_from_csv('test_publish__ok__cbers4a_mux_l4_dn.csv')

        assert_frame_equal(expected, result)

    def test_publish__ok__cbers4a_mux_l4_dn__geo_processing_does_not_exist(self):
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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull']) # empty dataframe

        assert_frame_equal(expected, result)

    def test_publish__ok__cbers4a_mux_l4_dn_or_sr__quicklook_does_not_exist(self):
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

        expected = [
            {
                'type': 'warning',
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {
                    'folder': '/TIFF/CBERS4A/2019_12/CBERS_4A_MUX_RAW_2019_12_28.14_15_00/221_108_0/4_BC_UTM_WGS84'
                }
            }
        ]

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull'])  # empty dataframe

        assert_frame_equal(expected, result)

    # CBERS4A WFI

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers4a_wfi_l4_dn.csv')

        assert_frame_equal(expected, result)

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers4a_wfi_l4_sr.csv')

        assert_frame_equal(expected, result)

    def test_publish__ok__cbers4a_wfi_l4_dn_and_sr(self):
        # 2020_12/CBERS_4A_WFI_RAW_2020_12_07.14_03_00_ETC2/214_108_0/4_BC_UTM_WGS84/
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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers4a_wfi_l4_dn_and_sr.csv')

        assert_frame_equal(expected, result)

    def test_publish__ok__cbers4a_wfi_l2_and_l4_sr(self):
        # 2020_12/CBERS_4A_WFI_RAW_2020_12_07.14_03_00_ETC2/214_108_0/4_BC_UTM_WGS84/
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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers4a_wfi_l2_and_l4_sr.csv')

        assert_frame_equal(expected, result)

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull'])  # empty dataframe

        assert_frame_equal(expected, result)

    def test_publish__ok__cbers4a_wfi__missing_geo_and_radio_processings(self):
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'wfi',
            'start_date': '2019-12-01',
            'end_date': '2020-06-30',
            'path': '215',
            'row': '132'
        }

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers4a_wfi__missing_geo_and_radio_processings.csv')

        assert_frame_equal(expected, result)

    def test_publish__ok__cbers4a_wfi__missing_path_and_row(self):
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'wfi',
            'start_date': '2019-12-01',
            'end_date': '2020-06-30',
            'geo_processing': '4',
            'radio_processing': 'DN'
        }

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers4a_wfi__missing_path_and_row.csv')

        assert_frame_equal(expected, result)

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers4a_wpm_l2_dn.csv')

        assert_frame_equal(expected, result)

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__cbers4a_wpm_l2_dn__next_to_5h.csv')

        assert_frame_equal(expected, result)

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

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull']) # empty dataframe

        assert_frame_equal(expected, result)

    # OTHER

    def test_publish__ok__l4_dn__missing_satellite_and_sensor(self):
        query = {
            'start_date': '2019-12-01',
            'end_date': '2020-06-30',
            'path': '215',
            'row': '132',
            'geo_processing': '4',
            'radio_processing': 'DN'
        }

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__ok__l4_dn__missing_satellite_and_sensor.csv')

        assert_frame_equal(expected, result)


class PublisherPublishLandsatOkTestCase(TestCase):

    @classmethod
    def setUpClass(cls):
        cls.api = app.test_client()
        cls.db = PostgreSQLTestConnection()

    def setUp(self):
        # clean table before testing
        self.db.delete_from_items()

    # LANDSAT1 MSS

    def test_publish__ok__landsat1_mss_l2_dn(self):
        # LANDSAT1/1973_05/LANDSAT1_MSS_19730521.120000/237_059_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'LANDSAT1',
            'sensor': 'MSS',
            'start_date': '1973-05-20',
            'end_date': '1973-05-21',
            'path': 237,
            'row': '059',
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('landsat/test_publish__ok__landsat1_mss_l2_dn.csv')

        assert_frame_equal(expected, result)

    def test_publish__ok__landsat1_mss_l2_dn__quicklook_does_not_exist(self):
        # LANDSAT1/1976_10/LANDSAT1_MSS_19761002.120000/010_057_0/2_BC_UTM_WGS84
        query = {
            'satellite': 'LANDSAT1',
            'sensor': 'MSS',
            'start_date': '1976-10-02',
            'end_date': '1976-10-02',
            'path': 10,
            'row': '057',
            'geo_processing': 2,
            'radio_processing': 'DN'
        }

        expected = [
            {
                'type': 'warning',
                'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                'metadata': {
                    'folder': '/TIFF/LANDSAT1/1976_10/LANDSAT1_MSS_19761002.120000/010_057_0/2_BC_UTM_WGS84'
                }
            }
        ]

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull'])  # empty dataframe

        assert_frame_equal(expected, result)


class PublisherPublishErrorTestCase(TestCase):

    @classmethod
    def setUpClass(cls):
        cls.api = app.test_client()
        cls.db = PostgreSQLTestConnection()

    def setUp(self):
        # clean table before testing
        self.db.delete_from_items()

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

        response = self.api.get('/publish', query_string=query)
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

        self.assertEqual(400, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull'])  # empty dataframe

        assert_frame_equal(expected, result)

    def test_publish__error__unknown_fields(self):
        query = {
            'satelliti': 'CBERS4A',
            'sensors': 'wfi',
            'date': '2019-12-01',
            'pathy': '215',
            'rown': '132',
            'processing': '4'
        }

        response = self.api.get('/publish', query_string=query)
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

        self.assertEqual(400, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull'])  # empty dataframe

        assert_frame_equal(expected, result)
