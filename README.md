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
$ python main.py
```
