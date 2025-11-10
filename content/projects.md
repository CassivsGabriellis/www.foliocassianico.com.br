+++
title = 'Projects'
description = "My projects."
summary = "Projects that I've made, hosted on Github."
[params]
  author = "Cássio Gabriel"
hideBackToTop = false
hidePagination = true
toc = false
readTime = true
+++

[www.foliocassianico.com.br](https://github.com/CassivsGabriellis/www.foliocassianico.com)

- This website is generated with the Hugo static site generator, which converts Markdown content into optimized HTML files hosted in an Amazon S3 bucket. Global content delivery and caching are powered by Amazon CloudFront, providing fast, secure HTTPS access through a certificate managed by AWS Certificate Manager. 
- The domain is registered with Registro.br, where DNS records route the `www` subdomain (CNAME) directly to the CloudFront distribution.
- To ensure clean routing and error handling, the architecture includes a Lambda@Edge (Origin Request) function that rewrites friendly URLs (for example, `/posts` → `/posts/index.html`), and a custom 404 error page configured in CloudFront to gracefully handle missing or restricted content. This setup prevents S3’s default “AccessDenied” XML responses and delivers a smooth user experience instead.
- Continuous deployment is fully automated through GitHub Actions, which builds the Hugo site and syncs it to S3 using an IAM user with minimal permissions. Additionally, a mirror copy of the website is published on GitHub Pages, serving as a public backup and alternative hosting source [here](https://cassivsgabriellis.github.io/).
> - This setup ensures performance, TLS security, continuous deployment, and redundancy between AWS and GitHub Pages.

[Server Performance Stats](https://github.com/CassivsGabriellis/server-performance-stats-script)
- A shell cript that shows the current stats of your server.

[Nginx Log Analyser](https://github.com/CassivsGabriellis/nginx-log-analyser)
- A shel script that reads a Nginx log file and provides top 5 log informations.

[Log Archive Tool](https://github.com/CassivsGabriellis/log-archive-tool)
- CLI tool/script to archive logs in a compressed file in a specified folder.