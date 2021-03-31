# publisher2

Second version of Publisher application.


## Installation

Install a specific Python version and create a virtualenv with it:

```
$ pyenv install 3.8.5 && \
    pyenv virtualenv 3.8.5 inpe_cdsr_publisher
```

Activate the virtualenv and install the dependencies inside it:

```
$ pyenv activate inpe_cdsr_publisher && \
    pip install -r requirements.txt
```


## Usage

First, you must have a [RabbitMQ](https://hub.docker.com/_/rabbitmq) and a [PostGIS](https://hub.docker.com/r/kartoza/postgis) services running. You can configure them using Docker containers.

Update the `environment.env` settings file according to your RabbitMQ and PostGIS services.

On a terminal, activate the virtualenv, set the proper environment variables and call the celery service:

```
$ pyenv activate inpe_cdsr_publisher && \
    set -a && source environment.env && set +a && \
    celery -A publisher.workers.processing worker -l INFO -Q processing
```

On another terminal, activate the virtualenv and set the proper environment variables again, and run the Flask application:

```
$ pyenv activate inpe_cdsr_publisher && \
    set -a && source environment.env && set +a && \
    flask run
```

Now, the application is running on http://localhost:5000/.


## Routes

### GET /publish

This route publishes scenes based on the parameters.
- Parameters:
    - `satellite` (mandatory): satellite name.
    - `sensor` (optional): satellite instrument name.
    - `start_date` (mandatory): start date using the following pattern: `YYYY-MM-DD`.
    - `end_date` (mandatory): end date using the following pattern: `YYYY-MM-DD`.
    - `path` (optional): path number.
    - `row` (optional): row number.
    - `geo_processing` (optional): geometric processing (e.g. `2` or `4`).
    - `radio_processing` (optional): radiometric processing (i.e. `DN` or `SR`)
- Response: if OK, the following message should be returned:
    ```
    /publish has been executed
    ```
- Error codes:
    - 400 (Bad Request): Invalid parameter.
    - 500 (Internal Server Error): Problem when publishing scenes. Please, contact the administrator.
- Examples:
    - Publish DN level 2 scenes of CBERS4A/MUX instrument from 2021-02-01 to 2021-02-28 on the 209/106 path/row:
        - http://localhost:5000/publish?satellite=CBERS4A&sensor=MUX&start_date=2021-02-01&end_date=2021-02-28&path=209&row=106&geo_processing=2&radio_processing=DN
    - Publish all available scenes of CBERS4A/MUX instrument from 2021-02-01 to 2021-02-28:
        - http://localhost:5000/publish?satellite=CBERS4A&sensor=MUX&start_date=2021-02-01&end_date=2021-02-28


## Testing

Before running the test cases for the first time, you need to initialize the test databases:

```
$ flask init-db
```

Run the test cases with `ERROR` logging level to suppress unnecessary logging messages:

```
$ export PR_LOGGING_LEVEL=ERROR &&
    python -m unittest discover tests "test_*.py" -v
```

Or, run the test cases and get coverage report:

```
$ export PR_LOGGING_LEVEL=ERROR &&
    coverage run -m unittest discover tests "test_*.py" -v &&
    coverage report -m &&
    coverage html
```


## Docker

Build the Docker image (development or production):

```
$ docker build -t inpe-cdsr-publisher -f Dockerfile . --no-cache
$ docker build -t registry.dpi.inpe.br/cdsr/publisher:0.0.4 -f Dockerfile . --no-cache
```

If you have credentials, then push the image to your registry. For example:

```
$ docker push registry.dpi.inpe.br/cdsr/publisher:0.0.4
```


## Usage

Run a Docker container using the previous Docker image:

```
$ docker run --name inpe_cdsr_publisher2 -p 5000:5000 \
    -v $(pwd):/app -v /data/TIFF:/TIFF \
    --env-file ./environment.env inpe-cdsr-publisher
```
