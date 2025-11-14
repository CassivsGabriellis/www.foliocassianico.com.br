+++
title = "Folio Cassianico (Architecture & Deployment)"
summary = "Why I built this site, the technologies I used, and how the whole architecture works."
date = 2025-11-13
toc = true
readTime = true
autonumber = true
tags = ["web-architecture", "system-design"]
+++

## Purpose of this Site

I wanted a personal space to publish my ideas, projects, thoughts, technical experiments, and solutions — something simple, practical, and fast to maintain. I also wanted a structure that embraced **automation**, **CI/CD**, **resilience**, and **security**, without the overhead of running servers or managing unnecessary complexity.

Using the [Hugo](https://gohugo.io/) static site generator gave me exactly that: a lightweight framework, trivial deployment, and a workflow I could automate entirely. Combined with AWS and GitHub Actions, it became a very efficient setup.

---

## Technology Diagram

To visualize this system, I used the Python library **[Diagrams](https://diagrams.mingrammer.com/)**, which allows you to write _architecture diagrams as code_.

This makes the architecture reproducible, version-controlled, and easy to iterate — and it documents the infrastructure in a clean, precise way.

![img](foliocassianico-architecture.png "Site architecture")

### Architecture Diagram (Code)

```python
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import CloudFront
from diagrams.aws.storage import S3
from diagrams.aws.management import Cloudwatch
from diagrams.aws.security import CertificateManager, IAM
from diagrams.aws.compute import Lambda
from diagrams.aws.general import InternetAlt1
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.vcs import Github
from diagrams.custom import Custom

graph_attrs = {
    "splines": "spline",
    "pad": "0.5",
    "nodesep": "0.6",
    "ranksep": "0.8",
}

node_attrs = {
    "fontsize": "12",
}

with Diagram(
    "www.foliocassianico.com.br Architecture",
    show=False,
    filename="www-foliocassianico-architecture",
    direction="LR",
    graph_attr=graph_attrs,
    node_attr=node_attrs,
    outformat=["png"]
):

    # Client & DNS Layer
    with Cluster("Client & DNS"):
        user = InternetAlt1("User Browser")
        dns = Custom("Registro.br\nDNS (CNAME → CloudFront)", "./registro-dot-br_logo.png")
        user >> dns

    # CI/CD & Source
    with Cluster("CI/CD & Source"):
        gh_repo = Github("GitHub Repo\n(content + config)")
        gh_actions = GithubActions("GitHub Actions\nBuild → S3/CF → GitHub Pages")
        iam_role = IAM("IAM Role\nS3Deployer (OIDC)")
        gh_pages = Github("GitHub Pages\nMirror Site")
        gh_repo >> gh_actions

    # AWS Platform
    with Cluster("AWS"):
        hugo = Custom("Hugo Static Files", "./hugo.png")

        cloudfront = CloudFront("CloudFront CDN\nHTTPS + Caching")
        acm = CertificateManager("ACM\nTLS Certificate")

        # Explicit representation of OAI/OAC
        oai = IAM("OAI / OAC\nOrigin Access Control")

        s3 = S3("Amazon S3\nPrivate Origin Bucket\n(only via OAI/OAC)")

        lambda_edge = Lambda("Lambda@Edge\nURL Rewrite\n/index.html")
        cw = Cloudwatch("CloudWatch\nLogs & Metrics")

        cloudfront >> acm
        lambda_edge >> cw
        cloudfront >> cw

    # Flow Logic

    # User traffic
    dns >> cloudfront

    # CloudFront → OAI/OAC → Lambda@Edge → S3 origin
    cloudfront >> Edge(label="Authenticated Origin Request") >> oai
    oai >> Edge(label="Authorized access") >> lambda_edge
    lambda_edge >> Edge(label="Fetch content") >> s3

    # CI/CD: Build
    gh_actions >> Edge(label="Build job\n(Hugo + Dart Sass)") >> hugo
    hugo >> Edge(label="Static files\n(artifact: hugo-site)") >> s3

    # CI/CD: Deploy to S3 + CloudFront invalidation
    gh_actions >> Edge(label="OIDC AssumeRole") >> iam_role
    iam_role >> Edge(label="aws s3 sync ./public → S3\n--delete --cache-control=31536000") >> s3
    iam_role >> Edge(label="CloudFront Invalidation\npaths: /*") >> cloudfront

    # Deploy GitHub Pages (mirror)
    gh_actions >> Edge(label="Deploy GitHub Pages\n(GH_TOKEN + git push -f)") >> gh_pages
    user >> Edge(label="Alternative Access", style="dashed") >> gh_pages

    # Custom 404
    cloudfront >> Edge(label="Custom 404\n(no XML errors)") >> s3
````

---

## How the System Works (Practical Overview)

The architecture explained in a clear and concise way:

### **Static Site Generation (Hugo)**

* All content is written in Markdown.
* Hugo generates minified, optimized HTML/CSS/JS.
* Builds run both locally and inside GitHub Actions.
* The output is stored in the `public/` directory.

---

### **Hosting on AWS (S3 + CloudFront + ACM)**

* The site is hosted on an **Amazon S3 bucket**, configured as a **private origin**.
* Only **CloudFront** can read from this bucket (via **OAI/OAC**).
* **CloudFront** provides:

  * global caching
  * HTTPS
  * higher availability
  * shorter latency
* TLS certificates are issued and maintained by **AWS Certificate Manager (ACM)**.

---

### **Rewriting URLs (Lambda@Edge)**

A custom Python Lambda@Edge (Origin Request) function:

* Rewrites URLs like `/posts` → `/posts/index.html`.
* Improves SEO and consistency.

#### `AddIndexHtmlToDirectoriesEdge`

A Python Lambda@Edge function that automatically rewrites clean URLs (like `/posts` or `/bio`) to their corresponding directory index files (`/posts/index.html`, `/bio/index.html`), ensuring static pages resolve correctly within the CloudFront + S3 architecture.

```python
def lambda_handler(event, context):
    # Extract the request from the CloudFront event
    cf_record = event['Records'][0]['cf']
    request = cf_record['request']
    uri = request.get('uri', '/')

    # If URI ends with "/", add "index.html"
    if uri.endswith('/'):
        uri += 'index.html'
    # If URI doesn't contain a dot (no extension), treat as a directory
    elif '.' not in uri:
        uri += '/index.html'

    # Update the request
    request['uri'] = uri

    # Return the modified request back to CloudFront
    return request
```

## CI/CD Pipeline (GitHub Actions)

All deployments occur automatically on every push to the repository’s `main` branch.

### Build Stage

GitHub Actions:

- Installs **Hugo Extended**
- Installs **Dart Sass**
- Checks out the repository (with submodules)
- Builds the site using:
  - `--minify`
  - `--baseURL`
  - production environment settings
- Uploads the compiled site (`hugo-site`) as a CI artifact

---

### Secure Deployment to AWS (OIDC + IAM Role)

To deploy safely to AWS **without storing access keys**, the pipeline uses **GitHub → AWS OIDC federation** to assume a dedicated IAM Role created specifically for this website:

### **IAM Role: `FolioCassianicoHugoBlog_S3Deployer`**

This role contains only the minimum permissions required for deployment.

#### **Policy 1 — S3 Bucket Minimum Privileges**

Allows uploading, updating, and deleting files in the website’s private S3 origin bucket:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "SyncToBucket",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::foliocassianico.com/*",
                "arn:aws:s3:::foliocassianico.com"
            ]
        }
    ]
}
```

This is the **exact minimum** needed for `aws s3 sync` to update the site.

#### **Policy 2 — Clean CloudFront Cache**

Allows the workflow to invalidate the CDN after deploying fresh content:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "FlushCache",
            "Effect": "Allow",
            "Action": "cloudfront:CreateInvalidation",
            "Resource": "arn:aws:cloudfront::885088828148:distribution/E3G12X4VILVRGQ"
        }
    ]
}
```

---

### **Trusted Entities (OIDC Trust Relationship)**

This IAM Role trusts only **GitHub Actions** from the exact repository responsible for deployment:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::885088828148:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:CassivsGabriellis/www.foliocassianico.com.br:*"
                }
            }
        }
    ]
}
```

This ensures:

* Only **GitHub Actions** for this exact repository can assume this IAM Role using short-lived, automatically rotated credentials with zero long-term AWS keys stored anywhere

---

### **AWS Deployment Steps**

Once GitHub Actions assumes the IAM Role:

1. It syncs the built site to S3:

   ```bash
   aws s3 sync ./public s3://foliocassianico.com --delete --cache-control max-age=31536000
   ```

2. It invalidates CloudFront to refresh the CDN:

   ```bash
   aws cloudfront create-invalidation --paths "/*"
   ```

#### **Mirror Deployment (GitHub Pages)**

A second deployment publishes the site to:

→ [https://cassivsgabriellis.github.io](https://cassivsgabriellis.github.io)

This acts as:

* an alternative public host
* a fully decoupled backup

---

## Summary

This architecture provides:

* **High performance** (CDN-cached static content)
* **Security** (private S3 + CloudFront OAI/OAC + IAM Role OIDC)
* **Resilience & redundancy** (GitHub Pages mirror)
* **Automation** (CI/CD from push → build → deploy → invalidation)
* **Zero servers to manage**

It’s a low-maintenance, cost-efficient, production-grade setup for a personal or professional portfolio.

If you're building your own static site, I highly recommend experimenting with Hugo, S3, CloudFront, Lambda@Edge, and GitHub Actions — it's a powerful combination.

>> You can see the remote repository of this project [here](https://github.com/CassivsGabriellis/www.foliocassianico.com.br).