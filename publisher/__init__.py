#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os

from flask import Flask

from publisher.environment import FLASK_SECRET_KEY, PR_BASE_DIR, PR_IS_TO_GET_DATA_FROM_DB
from publisher.publisher import Publisher


def create_app(test_config=None):
    '''Create Flask app.'''
    # source: https://flask.palletsprojects.com/en/1.1.x/tutorial/layout/

    # create and configure the app
    app = Flask(__name__, instance_relative_config=True)
    app.config.from_mapping(
        SECRET_KEY=FLASK_SECRET_KEY,
        # DATABASE=os.path.join(app.instance_path, 'flaskr.sqlite'),
    )

    if test_config is None:
        # load the instance config, if it exists, when not testing
        app.config.from_pyfile('config.py', silent=True)
    else:
        # load the test config if passed in
        app.config.from_mapping(test_config)

    # ensure the instance folder exists
    try:
        os.makedirs(app.instance_path)
    except OSError:
        pass

    @app.route('/')
    def index():
        return 'Hello, World! I\'m working!'

    @app.route('/publish')
    def publish():
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

        publisher_app = Publisher(
            PR_BASE_DIR, PR_IS_TO_GET_DATA_FROM_DB, query=query
        )
        publisher_app.main()

        return '/publish has been executed'

    return app
