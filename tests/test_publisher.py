from json import loads
from unittest import TestCase

from pandas import DataFrame, read_csv, to_datetime
from pandas.testing import assert_frame_equal

from publisher import create_app
from publisher.model import PostgreSQLTestConnection


test_config={'TESTING': True}
app = create_app(test_config)


def read_item_from_csv(file_name):
    expected = read_csv(f'tests/publisher/{file_name}')

    expected['start_date'] = to_datetime(expected['start_date'])
    expected['end_date'] = to_datetime(expected['end_date'])
    expected['assets'] = expected['assets'].astype('str')
    expected['metadata'] = expected['metadata'].astype('str')

    return expected


class PublisherPublishTestCase(TestCase):

    @classmethod
    def setUpClass(cls):
        cls.api = app.test_client()
        cls.db = PostgreSQLTestConnection()

    def setUp(self):
        # clean table before testing
        self.db.delete_from_items()

    def test_publish(self):
        response = self.api.get('/publish')

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish.csv')

        assert_frame_equal(expected, result)

    def test_publish__all_parameters__cbers4a_mux_l2_dn(self):
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
        expected = read_item_from_csv('test_publish__all_parameters__cbers4a_mux_l2_dn.csv')

        assert_frame_equal(expected, result)

    def test_publish__all_parameters__cbers4a_mux_l2_dn__next_to_0h(self):
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
        expected = read_item_from_csv('test_publish__all_parameters__cbers4a_mux_l2_dn__next_to_0h.csv')

        assert_frame_equal(expected, result)

    def test_publish__all_parameters__cbers4a_mux__invalid_query(self):
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

    def test_publish__all_parameters__cbers4a_wfi_l4_dn(self):
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'wfi',
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
        expected = read_item_from_csv('test_publish__all_parameters__cbers4a_wfi_l4_dn.csv')

        assert_frame_equal(expected, result)

    def test_publish__all_parameters__cbers4a_wfi_l4_sr(self):
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
        expected = read_item_from_csv('test_publish__all_parameters__cbers4a_wfi_l4_sr.csv')

        assert_frame_equal(expected, result)

    def test_publish__cbers4a_wfi_l4_dn_and_sr(self):
        # 2020_12/CBERS_4A_WFI_RAW_2020_12_07.14_03_00_ETC2/214_108_0/4_BC_UTM_WGS84/
        query = {
            'satellite': 'cbers4a',
            'sensor': 'wfi',
            'start_date': '2020-12-07',
            'end_date': '2020-12-07',
            'path': '214',
            'row': '108',
            'geo_processing': '4'
        }

        response = self.api.get('/publish', query_string=query)

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

        result = self.db.select_from_items()
        expected = read_item_from_csv('test_publish__cbers4a_wfi_l4_dn_and_sr.csv')

        assert_frame_equal(expected, result)

    def test_publish__all_parameters__cbers4a_wfi__invalid_query(self):
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'wfi',
            'start_date': '2020-09-01',
            'end_date': '2020-12-01',
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

    def test_publish__all_parameters__cbers4a_wpm_l2_dn(self):
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
        expected = read_item_from_csv('test_publish__all_parameters__cbers4a_wpm_l2_dn.csv')

        assert_frame_equal(expected, result)

    def test_publish__all_parameters__cbers4a_wpm_l2_dn__next_to_5h(self):
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
        expected = read_item_from_csv('test_publish__all_parameters__cbers4a_mux_l2_dn__next_to_5h.csv')

        assert_frame_equal(expected, result)

    def test_publish__all_parameters__cbers4a_wpm__invalid_query(self):
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

    def test_publish__all_parameters__invalid_values(self):
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

    def test_publish__unknown_fields(self):
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

    def test_publish__not_all_parameters__missing_geo_and_radio_processings(self):
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
        expected = read_item_from_csv('test_publish__not_all_parameters__missing_geo_and_radio_processings.csv')

        assert_frame_equal(expected, result)

    def test_publish__not_all_parameters__missing_path_and_row(self):
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
        expected = read_item_from_csv('test_publish__not_all_parameters__missing_path_and_row.csv')

        assert_frame_equal(expected, result)

    def test_publish__not_all_parameters__missing_satellite_and_sensor(self):
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
        expected = read_item_from_csv('test_publish__not_all_parameters__missing_satellite_and_sensor.csv')

        assert_frame_equal(expected, result)
