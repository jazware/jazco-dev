---
layout: post
title: "How to use ChatGPT to Write Good Code Faster"
excerpt: "ChatGPT has incredible potential for accelerating your development _flow_. When working on new projects and starting things from scratch, it allows you to rapidly iterate, make decisions that would usually mean a painful refactor, or make use of libraries and/or APIs you're unfamiliar with, without having to make 30 Google searches to read docs and StackOverflow samples."
---

There's been a lot of hype about Large Language Models (LLMs) lately with lots of cool examples of people using tools like [ChatGPT](https://chat.openai.com/chat) to draft Python scripts, Go code, and all sorts of other useful things.

Okay, so how do I use ChatGPT effectively?

## How do I Use ChatGPT Effectively?

To use ChatGPT effectively for writing code, I've found it's useful to treat it somewhat like an interview candidate.

To start, make sure you've selected the desired model if you're a ChatGPT Plus subscriber. If not, you'll be using the default model `gpt-3.5-turbo`:

![Select GPT-4 from the Model Selector](/public/images/2023-04-19/model_selection.png)

### Writing your First Prompt

Start with a broad description of the task you're trying to achieve. Let the model know that you want it to write code, and that you want it to be in a particular language. Describe the objective in plain English, providing examples of data structures you want it to make use of.

The following demo prompts and code are from a real conversation I had with ChatGPT enabling me to build some Deployment Metrics visualizations in support of a [DORA Metrics](https://cloud.google.com/blog/products/devops-sre/using-the-four-keys-to-measure-your-devops-performance) Initiative at work.

Start to finish, this project took ~2 hours with the second hour mostly being iterating on design of the charts and making sure important text was properly visible. Were I to write this myself from scratch, I could easily spend ~10-15 hours on it and would likely have settled for a less polished final product.

Deployments are handled through a GitOps flow and thus every deployment has a corresponding MR in GitLab, I'm interested in visualizing them on a per-service and per-environment basis.

#### Prompt to ChatGPT

> I'd like to write a Python script to use the GitLab API to collect statistics about merge requests for a specific repo. Merge requests in this repo have Labels that identify a `service`, i.e. `service:<service_name>` and a tier `tier:<tier_name>`. Closed Merge Requests should be considered "failed" deployments, Merged merge requests should be considered "successful" deployments. I'm using a private GitLab instance that I authenticate to with a private token. I'd like to efficiently write this script, the repo in question has tens of thousands of merge requests. I'd like the output to be a JSON file where the top level key is the service name. Each key should have a list of deployments containing the timestamp of the MR creation as the "deployment_time" and a "deployment_status" of either "successful" or "failed". I'd also like to generate a summary for each service that shows the number of deployments per month and the failure rate for deployments on a monthly basis. Make sure to use asyncio libraries where applicable for performance.

#### Response from ChatGPT

> To achieve this, you can use the `aiohttp` library for making asynchronous HTTP requests and `asyncio` for handling asynchronous tasks. We'll start by installing the required libraries:
>
> ```bash
> pip install aiohttp
> ```
>
> Here's a Python script that fulfills your requirements:
>
> ```python
>    import asyncio
>    import aiohttp
>    import json
>    from datetime import datetime
>    from collections import defaultdict
>
>    GITLAB_API_URL = "https://your-gitlab-instance-url.com/api/v4"
>    PRIVATE_TOKEN = "your-private-token"
>    PROJECT_ID = "your-project-id"
>
>    async def fetch_merge_requests(session):
>        url = f"{GITLAB_API_URL}/projects/{PROJECT_ID}/merge_requests"
>        headers = {"Private-Token": PRIVATE_TOKEN}
>        params = {"state": "all", "per_page": 100}
>        merge_requests = []
>
>        async with session.get(url, headers=headers, params=params) as response:
>            merge_requests.extend(await response.json())
>            total_pages = int(response.headers["X-Total-Pages"])
>
>        for page in range(2, total_pages + 1):
>            params["page"] = page
>            async with session.get(url, headers=headers, params=params) as response:
>                merge_requests.extend(await response.json())
>
>        return merge_requests
>
>    def parse_merge_requests(merge_requests):
>        service_deployments = defaultdict(list)
>
>        for mr in merge_requests:
>            service = None
>            tier = None
>
>            for label in mr["labels"]:
>                if label.startswith("service:"):
>                    service = label[8:]
>                elif label.startswith("tier:"):
>                    tier = label[5:]
>
>            if not service or not tier:
>                continue
>
>            deployment_time = datetime.strptime(mr["created_at"], "%Y-%m-%dT%H:%M:%S.%fZ")
>            deployment_status = "successful" if mr["state"] == "merged" else "failed"
>
>            service_deployments[service].append({
>                "deployment_time": deployment_time,
>                "deployment_status": deployment_status
>            })
>
>        return service_deployments
>
>    def generate_summary(service_deployments):
>        summary = defaultdict(lambda: defaultdict(int))
>
>        for service, deployments in service_deployments.items():
>            for deployment in deployments:
>                month_key = deployment["deployment_time"].strftime("%Y-%m")
>                summary[service][month_key] += 1
>
>        for service, deployments in service_deployments.items():
>            for deployment in deployments:
>                month_key = deployment["deployment_time"].strftime("%Y-%m")
>                if deployment["deployment_status"] == "failed":
>                    summary[service][f"{month_key}_failed"] += 1
>
>        for service, counts in summary.items():
>            for month_key, total_deployments in counts.items():
>                if "_failed" in month_key:
>                    continue
>
>                failed_key = f"{month_key}_failed"
>                failed_deployments = counts[failed_key]
>                failure_rate = (failed_deployments / total_deployments) * 100
>                summary[service][f"{month_key}_failure_rate"] = round(failure_rate, 2)
>
>        return summary
>
>    async def main():
>        async with aiohttp.ClientSession() as session:
>            merge_requests = await fetch_merge_requests(session)
>            service_deployments = parse_merge_requests(merge_requests)
>            summary = generate_summary(service_deployments)
>
>        with open("service_deployments.json", "w") as f:
>            json.dump(service_deployments, f, default=str, indent=2)
>
>        with open("summary.json", "w") as f:
>            json.dump(summary, f, indent=2)
>
>    if __name__ == "__main__":
>        asyncio.run(main())
> ```

### Iterating on Code and Ideas

ChatGPT is capable of iterating on past output, it gets fed into the model [Context](#context) along with your next message to turn the thread into a proper contextually aware conversation.

You can prompt ChatGPT to make alterations to code, restructure it, add new functions, or translate it into another programming language.

In the demo above, the code didn't quite work on the first try, so I ask ChatGPT to add some debug logging to it:

#### Prompt to ChatGPT

> Can we update the following function to handle errors properly and use the logging library to give some debug information?
>
> ```python
> async def fetch_merge_requests(session: ClientSession) -> List[Dict[str, Any]]:
>     url = f"{GITLAB_API_URL}/projects/{PROJECT_ID}/merge_requests"
>     headers = {
>         "Private-Token": PRIVATE_TOKEN,
>         "User-Agent": "ide-dora-metrics-client/1.0.1",
>     }
>     params = {"state": "all", "per_page": 100}
>     merge_requests = []
>
>     async with session.get(url, headers=headers, params=params) as response:
>         merge_requests.extend(await response.json())
>         total_pages = int(response.headers["X-Total-Pages"])
>
>     for page in range(2, total_pages + 1):
>         params["page"] = page
>         async with session.get(url, headers=headers, params=params) as response:
>             merge_requests.extend(await response.json())
>
>     return merge_requests
> ```

#### Response from ChatGPT

> To update the `fetch_merge_requests` function to handle errors and use the `logging` library for debug information, you can make the following changes:
>
> 1. Import the `logging` library and configure the logging level.
> 2. Add error handling using `try` and `except` blocks around the HTTP requests.
> 3. Add debug logging statements to help track the progress and potential issues.
>
> Here's the updated function with these changes:
>
> ```python
> import logging
>
> logging.basicConfig(level=logging.DEBUG)
> logger = logging.getLogger(__name__)
>
> async def fetch_merge_requests(session: ClientSession) -> List[Dict[str, Any]]:
>     url = f"{GITLAB_API_URL}/projects/{PROJECT_ID}/merge_requests"
>     headers = {
>         "Private-Token": PRIVATE_TOKEN,
>         "User-Agent": "ide-dora-metrics-client/1.0.1",
>     }
>     params = {"state": "all", "per_page": 100}
>     merge_requests = []
>
>     try:
>         async with session.get(url, headers=headers, params=params) as response:
>             if response.status == 200:
>                 merge_requests.extend(await response.json())
>                 total_pages = int(response.headers["X-Total-Pages"])
>                 logger.debug(f"Fetched page 1 of {total_pages} from GitLab API")
>             else:
>                 logger.error(f"Failed to fetch page 1, status: {response.status}")
>                 return merge_requests
>     except Exception as e:
>         logger.error(f"Error fetching page 1: {e}")
>         return merge_requests
>
>     for page in range(2, total_pages + 1):
>         params["page"] = page
>         try:
>             async with session.get(url, headers=headers, params=params) as response:
>                 if response.status == 200:
>                     merge_requests.extend(await response.json())
>                     logger.debug(f"Fetched page {page} of {total_pages} from GitLab API")
>                 else:
>                     logger.error(f"Failed to fetch page {page}, status: {response.status}")
>         except Exception as e:
>             logger.error(f"Error fetching page {page}: {e}")
>
>     return merge_requests
> ```
>
> Now, the function logs debug information and handles errors appropriately while fetching merge requests from the GitLab API.

After running the above code, I was getting an error trying to find the `X-Total-Pages` header from the response, it seemed to be missing but there was an `X-Next-Page` header, so I went back to ChatGPT to help me out:

#### Prompt to ChatGPT

> The response from GitLab's API doesn't have an `x-total-pages` header but it does have a `x-next-page` header. Can we refactor the function to handle that?

#### Response from ChatGPT

> Yes, you can refactor the function to use the `x-next-page` header instead of the `x-total-pages` header. You can do this by checking if the `x-next-page header` is present and has a value greater than the current page. Here's the updated function:
>
> ```python
> async def fetch_merge_requests(session: ClientSession) -> List[Dict[str, Any]]:
>     url = f"{GITLAB_API_URL}/projects/{PROJECT_ID}/merge_requests"
>     headers = {
>         "Private-Token": PRIVATE_TOKEN,
>         "User-Agent": "ide-dora-metrics-client/1.0.1",
>     }
>     params = {"state": "all", "per_page": 100}
>     merge_requests = []
>     page = 1
>
>     while True:
>         params["page"] = page
>         try:
>             async with session.get(url, headers=headers, params=params) as response:
>                 if response.status == 200:
>                     merge_requests.extend(await response.json())
>                     logger.debug(f"Fetched page {page} from GitLab API")
>
>                     next_page = response.headers.get("X-Next-Page")
>                     if next_page and int(next_page) > page:
>                         page += 1
>                     else:
>                         break
>                 else:
>                     logger.error(f"Failed to fetch page {page}, status: {response.status}")
>                     break
>         except Exception as e:
>             logger.error(f"Error fetching page {page}: {e}")
>             break
>
>     return merge_requests
>
> ```
>
> This refactored function now uses the `x-next-page` header to control the loop, and it fetches merge requests until there are no more pages available.

### Making your Code Faster

This code worked fine, but I noticed quickly it was going to take a really long time to run since we weren't using a `for` loop anymore and so we weren't leveraging the `async` HTTP client session effectively. With nearly 850 pages of Merge Requests to fetch, I got impatient fast, so instead of waiting 20 minutes for everything to finish, I asked ChatGPT to speed it up for me.

This is where ChatGPT really starts to show its value, and where you can see the analogue of a Technical Interview starts to fit. Fairly ambiguous statements that hint at a solution to a problem can help the model provide efficient and complete solutions.

#### Prompt to ChatGPT

> If I know there are at least 800 pages, is there a way we can structure this to run more concurrently?

#### Response from ChatGPT

> Yes, you can use `asyncio.gather` to run multiple requests concurrently. You can create a list of tasks and fetch multiple pages at the same time. Here's the updated `fetch_merge_requests` function that runs more concurrently:
>
> ```python
> async def fetch_page(session: ClientSession, url: str, headers: Dict[str, str], params: Dict[str, Any], page: int) -> List[Dict[str, Any]]:
>     params["page"] = page
>     try:
>         async with session.get(url, headers=headers, params=params) as response:
>             if response.status == 200:
>                 logger.debug(f"Fetched page {page} from GitLab API")
>                 return await response.json()
>             else:
>                 logger.error(f"Failed to fetch page {page}, status: {response.status}")
>                 return []
>     except Exception as e:
>         logger.error(f"Error fetching page {page}: {e}")
>         return []
>
> async def fetch_merge_requests(session: ClientSession) -> List[Dict[str, Any]]:
>     url = f"{GITLAB_API_URL}/projects/{PROJECT_ID}/merge_requests"
>     headers = {
>         "Private-Token": PRIVATE_TOKEN,
>         "User-Agent": "ide-dora-metrics-client/1.0.1",
>     }
>     params = {"state": "all", "per_page": 100}
>     merge_requests = []
>
>     # Fetch the first page to get the `x-next-page` header
>     first_page = await fetch_page(session, url, headers, params, 1)
>     merge_requests.extend(first_page)
>
>     # Assuming at least 800 pages
>     total_pages = 800
>     concurrent_pages = 10  # Adjust this number based on the desired level of concurrency
>
>     for page_start in range(2, total_pages + 1, concurrent_pages):
>         tasks = [
>             fetch_page(session, url, headers, params, page)
>             for page in range(page_start, page_start + concurrent_pages)
>         ]
>         pages = await asyncio.gather(*tasks)
>         for page_data in pages:
>             merge_requests.extend(page_data)
>
>     return merge_requests
> ```
>
> In this updated version, the `fetch_merge_requests` function calls a separate `fetch_page` function that retrieves a single page of merge requests. It then uses `asyncio.gather` to fetch multiple pages concurrently.
>
> You can adjust the `concurrent_pages` variable to control the level of concurrency. Note that setting this value too high may lead to rate-limiting issues or resource exhaustion. Make sure to find a balance that works for your specific use case and GitLab instance.

Incredible, this is exactly what I was looking for! It grabbed the data much faster now and gave me an easy way to tweak the performance by tuning the concurrency batch size. I ran into an error after the data was downloaded though, and needed help with the fix:

### Reading Error Messages and Self Correction

ChatGPT is really good at self-correction. It doesn't have an IDE built in (yet) and so it can't run the code for you to make sure it works (though the [Code Interpreter ChatGPT Plugin](https://openai.com/blog/chatgpt-plugins#:~:text=of%20the%20ecosystem.-,Code%20interpreter,-Alpha) will allow it to do this), but it's very good at reading error messages and correcting code it wrote. It's generally a good idea to provide the source code back to ChatGPT so the context doesn't get stale.

#### Prompt to ChatGPT

> I'm getting the following error:
>
> ```
> Traceback (most recent call last):
>   File "/Users/jaz/Documents/work/dora-metrics/deployment-metrics/get_data.py", line 142, in <module>
>     asyncio.run(main())
>   File "/opt/homebrew/Cellar/python@3.11/3.11.2_1/Frameworks/Python.framework/Versions/3.11/lib/python3.11/asyncio/runners.py", line 190, in run
>     return runner.run(main)
>            ^^^^^^^^^^^^^^^^
>   File "/opt/homebrew/Cellar/python@3.11/3.11.2_1/Frameworks/Python.framework/Versions/3.11/lib/python3.11/asyncio/runners.py", line 118, in run
>     return self._loop.run_until_complete(task)
>            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
>   File "/opt/homebrew/Cellar/python@3.11/3.11.2_1/Frameworks/Python.framework/Versions/3.11/lib/python3.11/asyncio/base_events.py", line 653, in run_until_complete
>     return future.result()
>            ^^^^^^^^^^^^^^^
>   File "/Users/jaz/Documents/work/dora-metrics/deployment-metrics/get_data.py", line 132, in main
>     summary = generate_summary(service_deployments)
>               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
>   File "/Users/jaz/Documents/work/dora-metrics/deployment-metrics/get_data.py", line 116, in generate_summary
>     for month_key, total_deployments in counts.items():
> RuntimeError: dictionary changed size during iteration
> ```
>
> The Generate Summary function looks like this:
>
> ```python
> def generate_summary(
>     service_deployments: DefaultDict[str, List[Dict[str, Any]]]
> ) -> DefaultDict[str, DefaultDict[str, float]]:
>     summary: Dict[str, DefaultDict[str, float]] = defaultdict(lambda: defaultdict(int))
>
>     for service, deployments in service_deployments.items():
>         for deployment in deployments:
>             month_key = deployment["deployment_time"].strftime("%Y-%m")
>             summary[service][month_key] += 1
>
>     for service, deployments in service_deployments.items():
>         for deployment in deployments:
>             month_key = deployment["deployment_time"].strftime("%Y-%m")
>             if deployment["deployment_status"] == "failed":
>                 summary[service][f"{month_key}_failed"] += 1
>
>     for service, counts in summary.items():
>         for month_key, total_deployments in counts.items():
>             if "_failed" in month_key:
>                 continue
>
>             failed_key = f"{month_key}_failed"
>             failed_deployments = counts[failed_key]
>             failure_rate = (failed_deployments / total_deployments) * 100
>             summary[service][f"{month_key}_failure_rate"] = round(failure_rate, 2)
>
>     return summary
> ```

#### Response from ChatGPT

> The error is caused by modifying the dictionary while iterating over it. To resolve the issue, you can separate the iteration and modification of the dictionary into two separate loops. In this case, we can iterate over the dictionary's keys and values in the first loop, and then iterate over the keys in the second loop to calculate and add the failure rate. Here's the modified `generate_summary` function:
>
> ```python
> def generate_summary(
>     service_deployments: DefaultDict[str, List[Dict[str, Any]]]
> ) -> DefaultDict[str, DefaultDict[str, float]]:
>     summary: Dict[str, DefaultDict[str, float]] = defaultdict(lambda: defaultdict(int))
>
>     for service, deployments in service_deployments.items():
>         for deployment in deployments:
>             month_key = deployment["deployment_time"].strftime("%Y-%m")
>             summary[service][month_key] += 1
>
>     for service, deployments in service_deployments.items():
>         for deployment in deployments:
>             month_key = deployment["deployment_time"].strftime("%Y-%m")
>             if deployment["deployment_status"] == "failed":
>                 summary[service][f"{month_key}_failed"] += 1
>
>     for service in summary.keys():
>         counts = summary[service]
>         month_keys = [key for key in counts.keys() if "_failed" not in key]
>
>         for month_key in month_keys:
>             total_deployments = counts[month_key]
>             failed_key = f"{month_key}_failed"
>             failed_deployments = counts[failed_key]
>             failure_rate = (failed_deployments / total_deployments) * 100
>             summary[service][f"{month_key}_failure_rate"] = round(failure_rate, 2)
>
>     return summary
> ```
>
> Now, the `generate_summary` function calculates the failure rate without causing a `RuntimeError`.

Great, now the script works just as expected and we've put it together in record time!

How do I preserve the operational information though? I want to write a Readme that will help the next person to need this script.

### Documentation

ChatGPT also excels at writing documentation for code. It can inline documentation as comments, explaining what code does or, if it's been party to the development, explain _why_ code is needed. It's also great at writing operational docs like a Readme or a Runbook.

#### Prompt to ChatGPT

> Can you write a README.md for running this script now?

#### Response from ChatGPT

> Here's a README.md for running the script:
>
> # Deployment Metrics
>
> This script collects deployment metrics from a GitLab repository using the GitLab API. It gathers statistics about merge requests with Labels identifying a `service` (e.g., `service:<service_name>`) and a tier (e.g., `tier:<tier_name>`). Closed merge requests are considered "failed" deployments, and merged merge requests are considered "successful" deployments.
>
> The output is a JSON file with the service name as the top-level key. Each key contains a list of deployments, including the timestamp of the merge request creation as "deployment_time" and a "deployment_status" of either "successful" or "failed". The script also generates a summary for each service, showing the number of deployments per month and the failure rate for deployments on a monthly basis.
>
> ## Requirements
>
> - Python 3.7 or higher
> - `aiohttp` library
>
> You can install the required `aiohttp` library using pip:
>
> ```bash
> pip install aiohttp
> ```
>
> ## Usage
>
> 1.  Set the following environment variables:
>     ```bash
>     export GITLAB_API_URL="https://your.gitlab.instance.com/api/v4"
>     export PRIVATE_TOKEN="your_private_token"
>     export PROJECT_ID="your_project_id"
>     export OUTPUT_FILE="output_file_name.json"
>     ```
>     Replace the placeholders with the appropriate values for your GitLab instance, private token, project ID, and desired output file name.
> 2.  Run the script:
>     ```bash
>     python deployment_metrics.py
>     ```
>     This will fetch the merge request data from the specified GitLab project, process the data, and generate the summary. The output JSON file will be saved in the current directory with the specified file name.
>
> ## Output
>
> The output JSON file will have the following structure:
>
> ```json
> {
>     "<service_name>": {
>         "<year-month>": <total_deployments>,
>         "<year-month>_failed": <failed_deployments>,
>         "<year-month>_failure_rate": <failure_rate>
>     },
>     ...
> }
> ```
>
> Example:
>
> ```json
> {
>   "service1": {
>     "2022-01": 10,
>     "2022-01_failed": 2,
>     "2022-01_failure_rate": 20.0
>   },
>   "service2": {
>     "2022-01": 8,
>     "2022-01_failed": 1,
>     "2022-01_failure_rate": 12.5
>   }
> }
> ```
>
> This README.md provides an overview of the script, its requirements, usage, and output. Users can follow the instructions to run the script and generate deployment metrics from a GitLab repository.

The provided Readme gets a few details wrong and the script has changed a bit, the environment variables aren't accurately named, but it gets the gist of what I'd write and after 2-3 minutes of touch-up, the Readme looks great!

### Expansion

Now that I've got some nice data, I'd like to visualize it. To be honest, writing a bunch of `matplotlib` graphs sounds like a huge PITA and I'd rather not have to dig around in the docs for an hour or two to get what I want. Thankfully, ChatGPT can expand on your existing problem and handle tasks like building graphs with ease.

#### Prompt to ChatGPT

> Given the `summary.json` as input, can we write a script to visualize the deployment frequency and failure rate of services? I'd also like to get a larger view of the monthly deployment rate and failure rate for all services combined.

#### Response from ChatGPT

> You can use the `matplotlib` library to visualize the deployment frequency and failure rate of services. First, you'll need to install the `matplotlib` library if you haven't already:
>
> ```bash
> pip install matplotlib
> ```
>
> Here's a script to visualize the data from the `summary.json` file:
>
> ```python
> import json
> from collections import defaultdict
> from typing import Dict
> import matplotlib.pyplot as plt
>
> def load_summary(file_name: str) -> Dict[str, Dict[str, float]]:
>     with open(file_name, "r") as f:
>         return json.load(f)
>
> def visualize(summary: Dict[str, Dict[str, float]]) -> None:
>     combined_summary = defaultdict(lambda: defaultdict(int))
>
>     for service, data in summary.items():
>         plt.figure(figsize=(10, 5))
>
>         months = sorted([key for key in data.keys() if "_failed" not in key and "_failure_rate" not in key])
>         deployment_counts = [data[month] for month in months]
>         failure_rates = [data[f"{month}_failure_rate"] for month in months]
>
>         plt.plot(months, deployment_counts, label="Deployments", marker="o")
>         plt.plot(months, failure_rates, label="Failure Rate", marker="o")
>         plt.xlabel("Month")
>         plt.ylabel("Deployments / Failure Rate (%)")
>         plt.title(f"{service} - Deployments and Failure Rate")
>         plt.legend()
>         plt.xticks(rotation=45)
>         plt.grid()
>         plt.savefig(f"{service}_deployment_metrics.png")
>         plt.show()
>
>         for month in months:
>             combined_summary[month]["deployments"] += data[month]
>             combined_summary[month]["failed"] += data[f"{month}_failed"]
>
>     plt.figure(figsize=(10, 5))
>
>     months = sorted(combined_summary.keys())
>     combined_deployments = [combined_summary[month]["deployments"] for month in months]
>     combined_failure_rates = [(combined_summary[month]["failed"] / combined_summary[month]["deployments"]) * 100 for month in months]
>
>     plt.plot(months, combined_deployments, label="Total Deployments", marker="o")
>     plt.plot(months, combined_failure_rates, label="Total Failure Rate", marker="o")
>     plt.xlabel("Month")
>     plt.ylabel("Deployments / Failure Rate (%)")
>     plt.title("Combined - Deployments and Failure Rate")
>     plt.legend()
>     plt.xticks(rotation=45)
>     plt.grid()
>     plt.savefig("combined_deployment_metrics.png")
>     plt.show()
>
> if __name__ == "__main__":
>     summary_data = load_summary("summary.json")
>     visualize(summary_data)
>
> ```

Awesome, now we're ready to start another iteration loop to make my charts look more like I envisioned them and parallelize generating thousands of them...

### Conclusion

ChatGPT has incredible potential for accelerating your development _flow_. When working on new projects and starting things from scratch, it allows you to rapidly iterate, make decisions that would usually mean a painful refactor, or make use of libraries and/or APIs you're unfamiliar with, without having to make 30 Google searches to read docs and StackOverflow samples.

While it doesn't do _all_ your work for you, it speeds up the iterative process immensely. ChatGPT is incredibly knowledgeable about a broad variety of language features and topics that no one else could hold in their head all at once. Make use of that property! It isn't going to write perfect code every time, and in many cases it may completely flub and hallucinate some nonsense because it doesn't have enough training in the niche you've asked it to perform. In those cases, since you're not even writing the code, it isn't really any time lost and usually there's something salvageable to work from or you can point out that the library it's trying to use doesn't exist and it should try to find another way.

I encourage you all to take advantage of this incredible new technology to improve your _flow_, spend more time debugging and thinking about how things should fit together and less time typing out an implementation. Spend more time in review and less time in boilerplate, allowing you to get tasks done with less individual effort. Don't forget to review the code ChatGPT gives you before running it, scrutinize it carefully if it's going to be doing something important or with a sizeable blast radius, and write tests for it as well (which ChatGPT can help with, just make sure you sanity check the actual test logic!).

## What is ChatGPT?

ChatGPT is the name of a product built by [OpenAI](https://openai.com/) that makes use of Generative Pre-trained Transformer machine learning models that takes in some Context and attempts to figure out what Tokens might come next.

### Context

Context is what we use to describe the input to the model. It generally consists of some kind of fixed initial prompt plus the history of your current conversation (any messages between you and the model since the thread started).

As far as I know, no one outside of OpenAI knows what ChatGPT's actual prompt is, but here's a trivial example:

> You are ChatGPT, a large language model trained by OpenAI. Answer as concisely as possible. Knowledge cutoff: 2021-09. Current date: 2023-04-19.

### Tokens

Tokens are units that the Context gets broken into, the model also generates Tokens as output. OpenAI describes their use and purpose well:

> The GPT family of models process text using tokens, which are common sequences of characters found in text. The models understand the statistical relationships between these tokens, and excel at producing the next token in a sequence of tokens. A helpful rule of thumb is that one token generally corresponds to ~4 characters of text for common English text. This translates to roughly ¾ of a word (so 100 tokens ~= 75 words).

You can test how your input may be tokenized using OpenAI's [Tokenizer Tool](https://platform.openai.com/tokenizer). This tool is useful because each model has a fixed maximum input Context Window. For [GPT-4](https://platform.openai.com/docs/models/gpt-4), this number is either 8,192 tokens for the `gpt-4` model and 32,768 tokens for the `gpt-4-32k` model. For GPT-3.5 (`gpt-3.5-turbo`), this number is 4,096 tokens. As far as I can tell, ChatGPT uses the `gpt-4` model when in GPT-4 mode, meaning you're generally restricted to around 8,000 tokens for your input strings. If you want to provide more context, try minifying your input using a tool like the [TSX Minifier](https://www.novel.tools/minify/tsx) for React Typescript code. Remember that while whitespace characters are sometimes just wasted tokens, in some languages like Python they have structural importance and can impact the performance/accuracy of the model.

### Model Output

The GPT-family of models produce "likely" output tokens given your input tokens. They try to treat the interaction as a conversation and guess what their character may say next in a conversation. Because GPT models are trained on such large internet-based datasets and have such high dimensionality, they have shown a surprising capability for writing working code in a variety of programming languages. Based on the training set data, the ChatGPT-family of models are best at Python but are competent in lots of other languages like Golang, Rust, Javascript, Typescript, Bash/Shell, and more.

## How do I Get Access to ChatGPT?

To access ChatGPT, sign up [here](https://chat.openai.com/chat) and create an account either with an email address or using OAuth via Google or Microsoft. Personally, I use the Google OAuth integration and haven't had any concerns about it.

Once you've logged in, you'll have free access to the basic model `gpt-3.5-turbo`. This model has a few drawbacks, mainly that it is an order of magnitude less "smart" than GPT-4 and you may find the code it produces is less frequently right on the first try.

### Upgrade to ChatGPT Plus to Gain Access to GPT-4

If you're interested in really leveraging the power of LLMs to increase productivity and/or running into the limits of `gpt-3.5-turbo` for complex tasks, I'd recommend upgrading to ChatGPT Plus for $20/mo which can be done in the ChatGPT web interface.

Note that even when a paying member of ChatGPT Plus, you'll be throttled in your usage of GPT-4 due to demand. Currently the throttling is set to 25 messages (of any context size) every 3 hours. If you're having very quick conversation with GPT-4, this can quickly vanish, so make sure your queries to it are more thought-out and specific to avoid wasting messages in your quota.
