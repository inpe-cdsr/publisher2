from unittest import TestCase

from numpy import nan as NaN
from pandas import read_csv, to_datetime
from pandas.testing import assert_frame_equal

from publisher import create_app
from publisher.environment import FLASK_TESTING
from publisher.model import PostgreSQLCatalogTestConnection, PostgreSQLPublisherConnection


app = create_app({'TESTING': FLASK_TESTING})

db = PostgreSQLCatalogTestConnection()
db_publisher = PostgreSQLPublisherConnection()

celery_async = ('publisher.workers.celery_config.task_always_eager', False)
celery_sync = ('publisher.workers.celery_config.task_always_eager', True)

test_delay_secs = 1.7


class BaseTestCases:
    class BaseTestCase(TestCase):
        maxDiff=None

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
            # result = db.select_from_items(to_csv=expected_file_path)
            # get the expected result
            expected = BaseTestCases.BaseTestCase.read_item_from_csv(expected_file_path)
            # fill pandas NaN (None, NaN, etc.) with numpy NaN
            expected.fillna({'min_convex_hull': NaN}, inplace=True)
            result.fillna({'min_convex_hull': NaN}, inplace=True)
            # print(f'\n expected.head(): \n{expected.head()}\n')
            # print(f' result.head(): \n{result.head()}\n')
            assert_frame_equal(expected, result)

        def check_if_the_items_table_is_empty(self):
            # check if the result size is equals to 0
            self.assertEqual(0, len(db.select_from_items().index))

        def check_if_the_errors_have_been_added_in_the_database(self, expected):
            # get the result from database
            result = db_publisher.select_from_task_error()
            self.assertEqual(expected, result)

    class ApiBaseTestCase(BaseTestCase):

        @classmethod
        def setUpClass(cls):
            cls.api = app.test_client()

        def get(self, url='/publish', query_string=None, expected='/publish has been executed',
                expected_status_code=200):
            response = self.api.get(url, query_string=query_string)

            self.assertEqual(expected_status_code, response.status_code)
            self.assertEqual(expected, response.get_data(as_text=True))
