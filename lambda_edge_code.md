### `AddIndexHtmlToDirectoriesEdge` Lambda@Edge function

`AddIndexHtmlToDirectoriesEdge` — a Python Lambda@Edge function that automatically rewrites clean URLs (like /posts or /about) to their corresponding directory index files (/posts/index.html, /about/index.html), ensuring static pages resolve correctly within the CloudFront + S3 architecture.

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
