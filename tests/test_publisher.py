from unittest import TestCase, main

from publisher import create_app
from publisher.model import PostgreSQLTestConnection


test_config={'TESTING': True}


class PublisherPublishTestCase(TestCase):

    @classmethod
    def setUpClass(cls):
        cls.app = create_app(test_config)
        cls.db = PostgreSQLTestConnection()

    def setUp(self):
        # clean table before testing
        self.db.delete_from_items()
        self.api = self.app.test_client()

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
