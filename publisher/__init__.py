#!/usr/bin/env python3
# -*- coding:utf-8 -*-

from json import dumps
from os import makedirs
from os.path import join as os_path_join

from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException

from publisher.environment import FLASK_SECRET_KEY, PR_BASE_DIR, PR_IS_TO_GET_DATA_FROM_DB, \
                                  PR_LOGGING_LEVEL
from publisher.logger import create_logger
from publisher.model import DBFactory, init_dbs
from publisher.publisher import Publisher


# create logger object
logger = create_logger(__name__, level=PR_LOGGING_LEVEL)


def create_app(test_config=None):
    '''Create Flask app.'''
    # source: https://flask.palletsprojects.com/en/1.1.x/tutorial/layout/

    ##################################################
    #                 CONFIGURATION                  #
    ##################################################

    # create and configure the app
    app = Flask(__name__, instance_relative_config=True)
    app.config.from_mapping(SECRET_KEY=FLASK_SECRET_KEY)

    if test_config is None:
        # load the instance config, if it exists, when not testing
        # `config.py` should be inside `app.instance_path` folder (i.e. /instance)
        app.config.from_pyfile('config.py', silent=True)
    else:
        # load the test config if passed in
        app.config.from_mapping(test_config)

    # create a db connection based on the environment variable
    db_connection = DBFactory.factory()

    try:
        # ensure the instance folder exists
        makedirs(app.instance_path)
    except OSError:
        pass

    ##################################################
    #                      CLI                       #
    ##################################################

    @app.cli.command('init-db')
    def init_db():
        init_dbs()

    ##################################################
    #                     ROUTES                     #
    ##################################################

    @app.errorhandler(HTTPException)
    def handle_exception(e):
        """Return JSON instead of HTML for HTTP errors."""
        # Source: https://flask.palletsprojects.com/en/1.1.x/errorhandling/#generic-exception-handlers
        # start with the correct headers and status code from the error
        response = e.get_response()
        # replace the body with JSON
        response.data = dumps({
            "code": e.code,
            "name": e.name,
            "description": e.description,
        })
        response.content_type = "application/json"
        return response

    @app.route('/')
    def index():
        return 'Hello, World! I\'m working!'

    @app.route('/publish')
    def publish():
        # `dict(request.args)`` returns the query string as a dict
        publisher_app = Publisher(
            PR_BASE_DIR, PR_IS_TO_GET_DATA_FROM_DB,
            db_connection, query=dict(request.args)
        )
        # execute main method
        publisher_app.main()
        return '/publish has been executed'

    return app
