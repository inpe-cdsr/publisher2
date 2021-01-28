from unittest import TestCase, main

from publisher import create_app


class PublisherIndexTestCase(TestCase):

    def setUp(self):
        self.app = create_app()

    def test_index(self):
        api = self.app.test_client()
        response = api.get('/')
        self.assertEqual(200, response.status_code)
        self.assertEqual('Hello, World! I\'m working!', response.get_data(as_text=True))


class PublisherPublishTestCase(TestCase):

    def setUp(self):
        self.app = create_app()

    def test_publish(self):
        api = self.app.test_client()
        response = api.get('/publish')
        self.assertEqual(200, response.status_code)
        self.assertEqual('/publish has been executed', response.get_data(as_text=True))


# if __name__ == '__main__':
#     main()
