# publisher2

Second version of publisher application.


## Installation

Install a specific Python version and create a virtualenv with it:

```
$ pyenv install 3.8.5 && \
    pyenv virtualenv 3.8.5 inpe_cdsr_publisher2
```

If necessary, install the dependencies inside the virtualenv:

```
$ pip install -r requirements.txt
```


## Usage

Activate the virtualenv and set the available environment variables:

```
$ pyenv activate inpe_cdsr_publisher2 && \
    set -a && source environment.env && set +a
```

Run the script:

```
$ flask run
```

## Testing

Before running the test cases for the first time, you need to initialize the databases:

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
$ docker build -t inpe-cdsr-publisher2 -f Dockerfile . --no-cache
$ docker build -t registry.dpi.inpe.br/cdsr/publisher:0.0.1 -f Dockerfile . --no-cache
```

If you have credentials, then push the image to your registry. For example:

```
$ docker push registry.dpi.inpe.br/cdsr/publisher:0.0.1
```


## Usage

Run a Docker container using the previous Docker image:

```
$ docker run --name inpe_cdsr_publisher2 -p 5000:5000 -v $(pwd):/app && \
    --env-file ./environment.env inpe-cdsr-publisher2
```
