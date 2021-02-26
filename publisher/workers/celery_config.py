# if True, run the tasks synchronously, else run them asynchronously
task_always_eager = False

# task_ignore_result = True

broker_transport_options = {
    'max_retries': 3,
    'interval_start': 0,
    'interval_step': 0.2,
    'interval_max': 0.5
}
