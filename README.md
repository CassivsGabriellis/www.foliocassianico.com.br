# Cássio Gabriel's personal website

[https://www.foliocassianico.com.br](https://www.foliocassianico.com.br)

- This website is generated with the Hugo static site generator, which converts Markdown content into optimized HTML files hosted in an Amazon S3 bucket. Global content delivery and caching are powered by Amazon CloudFront, providing fast, secure HTTPS access through a certificate managed by AWS Certificate Manager. 
- The domain is registered with Registro.br, where DNS records route the `www` subdomain (CNAME) directly to the CloudFront distribution.
- To ensure clean routing and error handling, the architecture includes a Python Lambda@Edge (Origin Request) function [code here](https://github.com/CassivsGabriellis/www.foliocassianico.com.br/blob/main/lambda_edge_code.md) that rewrites friendly URLs (for example, `/posts` → `/posts/index.html`), and a custom 404 error page configured in CloudFront to gracefully handle missing or restricted content. This setup prevents S3’s default “AccessDenied” XML responses and delivers a smooth user experience instead.
- Continuous deployment is fully automated through GitHub Actions, which builds the Hugo site and syncs it to S3 using an IAM user with minimal permissions. Additionally, a mirror copy of the website is published on GitHub Pages, serving as a public backup and alternative hosting source [here](https://cassivsgabriellis.github.io/).
> - This setup ensures performance, TLS security, continuous deployment, and redundancy between AWS and GitHub Pages.
