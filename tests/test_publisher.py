from os import environ
# set the environment variable before importing the app in order to set it correctly
environ['CELERY_ALWAYS_EAGER'] = 'False'

from unittest import TestCase


class PublisherOkTestCase(TestCase):

    def test__publisher(self):
        self.assertEqual(environ['CELERY_ALWAYS_EAGER'], 'False')
