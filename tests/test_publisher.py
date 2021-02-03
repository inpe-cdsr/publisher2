from json import loads
from unittest import TestCase

from pandas import DataFrame, read_csv, to_datetime
from pandas.testing import assert_frame_equal

from publisher import create_app
from publisher.model import PostgreSQLTestConnection


test_config={'TESTING': True}


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
        app = create_app(test_config)
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

    def test_publish__all_parameters__cbers4a_mux_geo_2(self):
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
        expected = read_item_from_csv('test_publish__all_parameters__cbers4a_mux_geo_2.csv')

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

        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull']) # empty dataframe

        assert_frame_equal(expected, result)

    def test_publish__all_parameters__cbers4a_wfi(self):
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
        expected = read_item_from_csv('test_publish__all_parameters__cbers4a_wfi.csv')

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

        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull'])  # empty dataframe

        assert_frame_equal(expected, result)

    def test_publish__all_parameters__cbers4a_wpm(self):
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
        expected = read_item_from_csv('test_publish__all_parameters__cbers4a_wpm.csv')

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

        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull']) # empty dataframe

        assert_frame_equal(expected, result)

    def test_publish__invalid_parameters__invalid_date_satelliti_sensors_parameters(self):
        query = {
            'satelliti': 'CBERS4A',
            'sensors': 'wfi',
            'date': '2019-12-01',
            'path': '215',
            'row': '132',
            'geo_processing': '4',
            'radio_processing': 'DN'
        }

        response = self.api.get('/publish', query_string=query)
        expected = {
            'code': 400,
            'name': 'Bad Request',
            'description': ("Invalid query. Errors: {'date': ['unknown field'], "
                            "'satelliti': ['unknown field'], 'sensors': ['unknown field']}")
        }

        self.assertEqual(400, response.status_code)
        self.assertEqual(expected, loads(response.get_data(as_text=True)))

        # check if the database if empty
        result = self.db.select_from_items()
        expected = DataFrame(columns=['name','collection_id','start_date','end_date','assets',
                                      'metadata','geom','min_convex_hull'])  # empty dataframe

        assert_frame_equal(expected, result)

    def test_publish__invalid_parameters__invalid_pathy_processing_rown_parameter(self):
        query = {
            'satellite': 'CBERS4A',
            'sensor': 'wfi',
            'start_date': '2019-12-01',
            'end_date': '2020-06-30',
            'pathy': '215',
            'rown': '132',
            'processing': '4'
        }

        response = self.api.get('/publish', query_string=query)
        expected = {
            'code': 400,
            'name': 'Bad Request',
            'description': ("Invalid query. Errors: {'pathy': ['unknown field'], "
                            "'processing': ['unknown field'], 'rown': ['unknown field']}")
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
