+++
title = "Folio Cassianico (Arquitetura & Implantação)"
summary = "O porquê deste site, as tecnologias que usei e como toda a arquitetura funciona."
date = 2025-11-13
toc = true
readTime = true
autonumber = true
tags = ["web-architecture", "system-design"]
+++

## Propósito deste Site

Eu queria um espaço pessoal para publicar minhas ideias, projetos, pensamentos, experimentos técnicos e soluções — algo simples, prático e rápido de manter. Também queria uma estrutura que levasse em conta **automação**, **CI/CD**, **resiliência** e **segurança**, sem a sobrecarga de executar servidores ou gerenciar complexidade desnecessária.

Usar o gerador de sites estáticos [Hugo](https://gohugo.io/) me trouxe exatamente isso: um *framework* leve, de fácil implantação (*deploy*) e um fluxo de trabalho que posso automatizar de forma completa. Combinado com AWS e GitHub Actions, a configuração do site em si tornou-se muito eficiente.

---

## Diagrama de Tecnologias

Para visualizar este sistema, utilizei a biblioteca Python **[Diagrams](https://diagrams.mingrammer.com/)**, que permite escrever _diagramas de arquitetura como código_.

Isso torna a arquitetura reproduzível, versionada e fácil de iterar — além de documentar a infraestrutura de forma limpa e precisa.

![img](foliocassianico-architecture.png "Arquitetura do site")

### Diagrama da Arquitetura (Código)

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

## Como o Site funciona (Apanhado Prático)

A arquitetura explicada de forma clara e objetiva:

### **Gerador estático de site (Hugo)**

* Todo o conteúdo é escrito em Markdown.
* O Hugo gera HTML/CSS/JS minimizados e otimizados.
* Os builds rodam tanto localmente quanto dentro do GitHub Actions.
* A saída é armazenada no diretório `public/`.

---

### **Hospedagem na AWS (S3 + CloudFront + ACM)**

* O site é hospedado em um **bucket Amazon S3**, configurado como **origem privada**.

* Apenas o **CloudFront** pode ler desse bucket (via **OAI/OAC**).

* O **CloudFront** fornece:

  * cache global
  * HTTPS
  * maior disponibilidade
  * menor latência

* Os certificados TLS são emitidos e gerenciados pelo **AWS Certificate Manager (ACM)**.

---

### **Reescrevendo URLs (Lambda@Edge)**

Uma função personalizada Lambda@Edge em Python (Origin Request):

* Reescreve URLs como `/posts` → `/posts/index.html`.
* Melhora SEO e consistência.

#### `AddIndexHtmlToDirectoriesEdge`

Uma função Lambda@Edge em Python que reescreve automaticamente URLs "limpas" (como `/posts` ou `/bio`) para seus arquivos `index.html` correspondentes (`/posts/index.html`, `/bio/index.html`), garantindo que páginas estáticas sejam resolvidas corretamente na arquitetura CloudFront + S3.

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

## Pipeline CI/CD (GitHub Actions)

Todas as implantações ocorrem automaticamente a cada push para a branch `main` do repositório.

### Fase de Construção (Build)

O GitHub Actions:

* Instala o **Hugo Extended**
* Instala o **Dart Sass**
* Faz checkout do repositório (com submódulos)
* Gera o site usando:

  * `--minify`
  * `--baseURL`
  * configurações de ambiente de produção
* Envia o site compilado (`hugo-site`) como artefato do CI

---

### Implantação Segura ao AWS (OIDC + IAM Role)

Para implantar de forma segura na AWS **sem armazenar chaves de acesso**, o pipeline usa **federação OIDC GitHub → AWS** para assumir uma Role IAM dedicada criada especificamente para este site.

### **Role IAM: `FolioCassianicoHugoBlog_S3Deployer`**

Esta *role* contém apenas as permissões mínimas necessárias para a implantação.

#### **Política 1 — Privilégios Mínimos ao S3 Bucket**

Permite enviar, atualizar e excluir arquivos no bucket S3 privado que serve como origem do site:

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

Estas são as permissões **mínimas** necessárias para que `aws s3 sync` atualize o site.

#### **Política 2 — Limpar o Cache do CloudFront**

Permite que o workflow invalide o CDN após publicar conteúdo novo:

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

### **Entidades de Confiança (Trusted Entities) (OIDC Trust Relationship)**

Esta IAM Role confia apenas no **GitHub Actions** do exato repositório responsável pela implantação:

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

Isso garante:

* Apenas o **GitHub Actions** deste repositório específico pode assumir esta IAM Role usando credenciais temporárias e automaticamente rotacionadas sem nenhuma chave AWS armazenada em lugar algum.

---

### **Passos para a Implantação na AWS**

Depois que o GitHub Actions assume a IAM Role:

1. Ele sincroniza o site compilado com o S3:

   ```bash
   aws s3 sync ./public s3://foliocassianico.com --delete --cache-control max-age=31536000
   ```

2. Ele invalida o CloudFront para atualizar o CDN:

   ```bash
   aws cloudfront create-invalidation --paths "/*"
   ```

#### **Implantação em Site Espelho (GitHub Pages)**

Uma segunda implantação publica o site em:

→ [https://cassivsgabriellis.github.io](https://cassivsgabriellis.github.io)

Funcionando como:

* um host público alternativo
* um backup totalmente independente

---

## Sumário

Esta arquitetura oferece:

* **Alta performance** (conteúdo estático em CDN)
* **Segurança** (S3 privado + CloudFront OAI/OAC + IAM Role OIDC)
* **Resiliência e redundância** (espelho no GitHub Pages)
* **Automação** (CI/CD: push → build → deploy → invalidation)
* **Zero servidores para gerenciar**

É uma configuração de baixo custo, baixa manutenção e nível de produção para um portfólio pessoal ou profissional.

Se você estiver construindo seu próprio site estático, recomendo experimentar Hugo, S3, CloudFront, Lambda@Edge e GitHub Actions — é uma combinação eficiente e poderosa.

>> O repositório remoto deste projeto pode ser acessado [aqui](https://github.com/CassivsGabriellis/www.foliocassianico.com.br).