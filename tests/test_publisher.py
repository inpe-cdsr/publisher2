from ast import literal_eval
from unittest import TestCase, main

from pandas import read_csv, to_datetime
from pandas.testing import assert_frame_equal

from publisher import create_app
from publisher.model import PostgreSQLTestConnection


test_config={'TESTING': True}


def read_item_from_csv(path):
    expected = read_csv(path)

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

    def test_publish_with_all_parameters(self):
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
        expected = read_item_from_csv('tests/publisher/test_publish_with_all_parameters.csv')

        assert_frame_equal(expected, result)

    def test_publish_with_not_all_parameters(self):
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

    def test_publish_with_invalid_parameters(self):
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

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))

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

        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))


# if __name__ == '__main__':
#     main()
