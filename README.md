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

Run the test cases with `WARNING` logging level to suppress unnecessary logging messages:

```
$ export PR_LOGGING_LEVEL=WARNING &&
    python -m unittest discover tests "test_*.py" -v
```


## Docker

Build the Docker image (development or production):

```
$ docker build -t inpe-cdsr-publisher2 -f Dockerfile . --no-cache
$ docker build -t registry.dpi.inpe.br/cdsr/publisher2:0.0.1 -f Dockerfile . --no-cache
```

If you have credentials, then push the image to your registry. For example:

```
$ docker push registry.dpi.inpe.br/cdsr/publisher2:0.0.1
```
