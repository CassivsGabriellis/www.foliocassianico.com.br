+++
Title = "Construindo uma API de métricas em AWS EC2 com FastAPI, k3s (Kubernetes), Terraform, Ansible e CI/CD com GitHub Actions"
summary = "API em FastAPI executando em um cluster k3s dentro de uma instância AWS EC2, expondo métricas de performance da máquina e da aplicação, provisionada com Terraform, configurada com Ansible e atualizada via GitHub Actions."
date = 2025-11-15
toc = true
readTime = true
autonumber = true
tags = ["cloud", "devops", "system-design", "aws", "ec2", "kubernetes", "k3s", "fastapi", "terraform", "ansible", "github actions", "ci/cd"]
+++

## Proprósito deste projeto

Em busca de aprofundar meus conhecimentos em arquitetura de nuvem e nas variadas formas de se construir ambientes em nuvem, decidi construir do zero uma API e provisioná-la em uma instância EC2 Linux para testar certos conceitos dos quais tenho aprendido nos últimos dias, este principalmente em meus estudos para certificação AWS Cloud Architect.

Objetivamente, desenvolvi uma API em Python (FastAPI) que coleta métricas da instância e da aplicação nela sendo executada e a coloquei para rodar em um cluster Kubernetes numa instância EC2 na AWS. Toda a infraestrutura é provisionada com Terraform, a configuração do servidor e do cluster é feita com Ansible, e o deploy é automatizado com GitHub Actions. O projeto foi pensado para ser integrado posteriormente com Prometheus e Grafana para observabilidade completa.

### Objetivos deste projeto

- Construir uma API simples que exporá métricas de performance da instância e da própria aplicação, em Python (servida pelo web framework FastAPI);
- Rodará num cluster Kubernetes dentro de uma instância AWS EC2 Linux;
- Será provisionada por Terraform (VPC, sub-rede, EC2, Security Groups, IAM);
- Configurada com Ansible (instala Docker, K3s, dependências, faz deploy);
- Atualizada via CI/CD com GitHub Actions (build da imagem e pull do DockerHub, push, deploy automático).

### Diagrama de arquitetura do projeto

![](images/metrics-api-k3s-ec2-cicd-architecture.png "Diagrama feito com a biblioteca Diagrams (Diagram as Code)")

---

## API com FastAPI

O papel desta API é expor métricas de desempenho tanto do host onde o pod está executando quanto da própria aplicação, isto é, a API em si, software backend escrito em Python, empacotado em Docker e executado dentro de um cluster Kubernetes — cujo propósito é coletar e expor métricas operacionais tanto do próprio ambiente onde está rodando quanto do seu estado interno.

Trata-se de uma camada fundamental para permitir integração futura com ferramentas de observabilidade como Prometheus e Grafana. Para isso, optei pelo framework [FastAPI](https://fastapi.tiangolo.com/), que oferece rotas rápidas, excelente performance assíncrona e um modelo interno de documentação automática. Essa escolha viabiliza uma comunicação eficiente entre os componentes distribuídos do cluster, além de proporcionar simplicidade na implementação dos endpoints.

O design da API serve os seguintes *endpoints*:
* `GET /health`: usado pelo Kubernetes para testes de Liveness e Readiness probe.
    * Exemplo:
    ```json
    {
        "status": "ok",
        "app": "k8s-cluster-performance-stack",
        "version": "1.0.0"
    }
    ```
* `GET /info`: fornece informações sobre a aplicação que está rodando na instância.
    * Exemplo:
    ```json
    {
        "app_name": "k8s-cluster-performance-stack",
        "version": "1.0.0",
        "environment": "dev",
        "server_time": "2025-11-15T15:30:00Z"
    }
    ```
* `GET /metrics/system`: métricas do host onde o *pod* está rodando.
    * Exemplo:
    ```json
    {
        "cpu": {
            "percent": 21.3,
            "cores": 2
        },
        "memory": {
            "total_mb": 993,
            "used_mb": 450,
            "percent": 45.3
        },
        "disk": {
            "total_gb": 20.0,
            "used_gb": 8.4,
            "percent": 42.0
        },
        "load_average": {
            "1m": 0.42,
            "5m": 0.36,
            "15m": 0.30
        }
    }
    ```
* `GET /metrics/app`: métricas da própria aplicação (em nível "aplicação").
    * Exemplo:
    ```json
    {
        "uptime_seconds": 1234,
        "requests_count": 87,
        "startup_time": "2025-11-15T15:00:00Z"
    }
    ```

As seguintes dependências são utilizadas como requisitos para que a API seja executada, estando localizadas em um arquivo `.txt` na raiz do repositório do projeto:
```
fastapi==0.121.3
uvicorn[standard]==0.38.0
psutil==7.1.3
python-dotenv==1.2.1
```

Para testar localmente, utilizei o [Uvicorn](https://uvicorn.dev/), uma implementação de servidor baseado no protocolo [ASGI](https://en.wikipedia.org/wiki/Asynchronous_Server_Gateway_Interface), em vistas de utilizar a seção `/docs` do FastAPI:
```
uvicorn app.main:app --reload
```

O repositório com o código da API pode ser acessado [aqui](https://github.com/CassivsGabriellis/metrics-api-k8s-cluster-performance/tree/main/app).

---

## Conteinerização da API com Docker

Dando continuidade, dá-se a conteinerização da API,  pois todo o restante da arquitetura depende de uma imagem consistente, padronizada e facilmente replicável. Para isso, crio um **Dockerfile** minimalista, baseado em uma imagem "slim" do Python 3.12, garantindo que o ambiente fosse leve, rápido para construir e adequado para rodar em máquinas com recursos limitados, como uma instância EC2 t3.small utilizada no Free Tier da AWS.

Dentro do Dockerfile, defino boas práticas essenciais como a configuração das variáveis de ambiente `PYTHONDONTWRITEBYTECODE` e `PYTHONUNBUFFERED`, que reduzem o overhead de escrita em disco e melhoram a observabilidade de logs. Em seguida, instala-se as dependências de compilação necessárias para pacotes como `psutil`, inclui-se o `requirements.txt` para instalar as dependências Python e copia-se o código da pasta `app/` para dentro da imagem. Por fim, configuro o container para expor a porta 8000 e rodar o servidor Uvicorn, permitindo que a API FastAPI responda requisições HTTP dentro do cluster Kubernetes.

### Arquivo Docker na raiz do projeto
```docker
# =========================
# 1) Builder: installs deps
# =========================
FROM python:3.12-slim AS builder

# Better logging and no .pyc
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Build dependencies (psutil, etc.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies in a venv
COPY requirements.txt .
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# =========================
# 2) Runtime: final image
# =========================
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Copy the already-prepared virtual environment
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy only the application code
COPY app ./app

# API port
EXPOSE 8000

# Default variables
ENV APP_ENV=prod

# Command to run the FastAPI API
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Build e push manual da imagem (para teste)
```bash
# Build the image
docker build -t cassiano00/metrics-api:latest .

# Test locally
docker run --rm -p 8000:8000 cassiano00/metrics-api:latest

# Push to Docker Hub (for Kubernetes to pull)
docker push cassiano00/metrics-api:latest
```

![](images/running-locally-docker.png)

---

## Orquestração em um cluster Kubernetes

Dada a imagem montada, orquestro um cluster Kubernetes através de manifests YAML. O primeiro componente criado foi o `namespace.yaml`, uma prática fundamental que organiza logicamente os recursos e evita conflitos entre serviços diferentes dentro do cluster. Criar o namespace **metrics-api** garante isolamento e facilita futuras operações de gerenciamento e automação.

Para testar localmente, utilizo o [Minikube](https://minikube.sigs.k8s.io), que implementa um cluster Kubernetes local.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: metrics-api
  labels:
    name: metrics-api
```

Aplicando as configurações presentes no arquivo `namespace.yaml`:
```bash
kubectl apply -f k8s/namespace.yaml
```

![](images/kubeclt-command-1.png)

Em seguida, definino o `deployment.yaml`, recurso central no Kubernetes responsável por gerenciar e manter a aplicação em execução de forma declarativa. No Deployment, configuro o lançamento de 1 (uma) réplica, visto que é um ambiente de teste. Especifico a imagem Docker construída anteriormente e adiciono _probes_ de liveness e readiness apontando para o endpoint `/health`. Essas _probes_ são essenciais para que o Kubernetes detecte automaticamente falhas de containers e garanta que somente instâncias saudáveis recebam tráfego. Além disso, configuro _requests_ e _limits_ de CPU e memória, evitando que o container consuma mais recursos do que deveria — o que é crítico em ambientes pequenos como um EC2 de baixo custo.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-api-deployment
  namespace: metrics-api
  labels:
    app: metrics-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: metrics-api
  template:
    metadata:
      labels:
        app: metrics-api
    spec:
      containers:
        - name: metrics-api
          image: cassiano00/metrics-api:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8000
          env:
            - name: APP_ENV
              value: "prod"
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 20
            timeoutSeconds: 2
            failureThreshold: 3
```

Executando as configurações:

```bash
kubectl apply -f k8s/deployment.yaml
```
![](images/kubeclt-command-2.png)

Com o Deployment definido, crio um `service.yaml` do tipo **ClusterIP** para fornecer um _endpoint_ interno estável que abstrai os pods. O Service expõe a porta `80` internamente e repassa chamadas para a porta `8000` do container, padronizando o acesso e permitindo que outros componentes, como o [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/), interajam com o backend sem depender da estrutura interna do Deployment. Esta é uma boa prática de isolamento em clusters.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: metrics-api-service
  namespace: metrics-api
  labels:
    app: metrics-api
spec:
  selector:
    app: metrics-api
  ports:
    - name: http
      port: 80
      targetPort: 8000
  type: ClusterIP
```
Aplicando as configurações:
```bash
kubectl apply -f k8s/service.yaml
```
![](images/kubeclt-command-3.png)

Finalizando a camada Kubernetes, implemento o arquivo `ingress.yaml`, responsável por fornecer uma interface HTTP externa ao cluster por meio do NGINX Ingress Controller. No ambiente local, onde o Minikube está sendo executado com driver Docker no Windows, o acesso direto ao IP interno do cluster não é possível. Por isso, utilizo o **`minikube tunnel`**, que cria uma rota entre o host e o Ingress Controller, expondo o tráfego de entrada de forma confiável em `127.0.0.1`.

Com essa configuração, o Ingress atua como o ponto de entrada oficial da aplicação dentro do cluster, mapeando requisições externas para o Service interno (`metrics-api-service:80`). Isso remove a necessidade de túneis temporários como o `minikube service ... --url` e garante um fluxo de tráfego idêntico ao utilizado em ambientes reais: cliente → Ingress NGINX → Service → Pods.

Ao centralizar o acesso externo no Ingress, a arquitetura se torna mais organizada, escalável e alinhada ao padrão utilizado em clusters Kubernetes de produção. Esse componente também habilita futuras extensões — como suporte a TLS, autenticação, rate limiting e roteamento avançado. Além disso, prepara naturalmente o ambiente para a futura integração com Prometheus e Grafana, facilitando a exposição de métricas, dashboards e observabilidade completa da aplicação.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: metrics-api-ingress
  namespace: metrics-api
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: metrics-api-service
                port:
                  number: 80
```

Executando as configurações:
```bash
kubectl apply -f k8s/ingress.yaml
```
![](images/kubeclt-command-4.png)

Testando o endpoint via comando `curl`:
```bash
curl http://127.0.0.1/health
curl http://127.0.0.1/metrics/system
```
![](images/kubeclt-command-5.png)

---

## Provisionando a infraestrutura via Terraform

Ao avançar para a etapa de infraestrutura do projeto, minha prioridade foi estabelecer uma base sólida e reprodutível para executar o cluster Kubernetes que futuramente hospedará a API de métricas. Para isso, iniciei pelo provisionamento da camada de rede e computação utilizando Terraform. O objetivo era garantir que toda a fundação da aplicação — desde a VPC até a instância EC2 — fosse criada de forma declarativa, auditável e consistente. Criei uma VPC dedicada, uma sub-rede pública e uma tabela de rotas conectada a um Internet Gateway, assegurando que a instância tivesse acesso à internet para instalar dependências, baixar imagens e operar o k3s sem restrições. Em seguida, configurei um Security Group com regras estritamente necessárias: acesso SSH para administração e portas HTTP/HTTPS abertas para o futuro Ingress Controller. Feito isso, defini uma instância EC2 **t3.small** — suficiente para um ambiente de validação — utilizando a AMI do Ubuntu 22.04, garantindo compatibilidade com Docker, k3s e demais ferramentas da stack.

Os seguinte itens serão provisionados em nuvem:

* 1 VPC
* 1 public subnet
* Internet gateway + route table
* 1 ElasticIP (fixed public Ip)
* 1 Security Group (SSH + HTTP/HTTPS)
* 1 instância EC2 (t3.small) que servirá como um node [k3s](https://docs.k3s.io/)

### Configurando a VPC
Comecei criando uma VPC dedicada com um bloco CIDR amplo (`10.0.0.0/16`), permitindo flexibilidade para expansão futura de sub-redes, balanceadores ou nós adicionais. Em seguida, configurei uma sub-rede pública (`10.0.1.0/24`) com `map_public_ip_on_launch` habilitado, garantindo que instâncias dentro dessa sub-rede recebessem um IP público automaticamente, eliminando a necessidade de Elastic IPs no ambiente de validação. Associei essa sub-rede a uma tabela de rotas contendo a rota padrão (`0.0.0.0/0`) direcionada para um Internet Gateway recém-criado, assegurando conectividade externa total — algo essencial para que o nó pudesse baixar pacotes, realizar pull de imagens Docker e se comunicar com registries públicos. Também provisionei um endereço IPv4 estático, através de um ElasticIP associado à instância.

**`main.tf`**:

```
# VPC
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
    tags = {
        Name = "${var.project_name}-vpc"
    }
  enable_dns_hostnames = true
  enable_dns_support = true
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                    = aws_vpc.this.id
  cidr_block                = "10.0.1.0/24"
  map_public_ip_on_launch   = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# Public Route Table for subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
    tags = {
        Name = "${var.project_name}-public-rt"
    }
}

...

# Elastic IP associated with the k3s_node instance
resource "aws_eip" "k3s_eip" {
  domain   = "vpc"
  instance = aws_instance.k3s_node.id

  tags = {
    Name = "${var.project_name}-eip"
  }
}
```
### Configurando um Security Group

Na parte de segurança, construí um Security Group seguindo o princípio do menor privilégio, liberando apenas o tráfego necessário: porta 22 para SSH (limitada via variável parametrizável), porta 80 para receber tráfego HTTP futuramente via Ingress e porta 443 para antecipar cenários de TLS. Todo o restante permaneceu bloqueado.

**`main.tf`**:

```
# Security Group for EC2 instance
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for metrics API k3s node"
  vpc_id      = aws_vpc.this.id

  # SSH access
  ingress {
    description      = "Allow SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = [var.allowed_ssh_cidr]
  }
  
  # HTTP access
  ingress {
    description      = "Allow HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  # HTTPS (for future TLS)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: allow everything
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}
```

### Configurando a instância EC2

Com a rede estabelecida, finalizei o provisionamento criando uma instância EC2 `t3.small`, suficiente para cenários de teste, utilizando a AMI oficial do Ubuntu 22.04. Essa escolha foi deliberada, dadas suas otimizações, compatibilidade plena com Docker e suporte nativo a **systemd** — fundamental para o funcionamento adequado dos serviços do k3s. Assim, toda a camada fundacional do cluster estava definida não apenas de manera declarativa, mas também calibrada para operar workloads containerizados.

**`main.tf`**:

```
# Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 instance that will run k3s
resource "aws_instance" "k3s_node" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = false 

  tags = {
    Name = "${var.project_name}-k3s-node"
  }
}
```
Antes deste processo, já havia configurado meu ambiente com o [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html), para que as devidas permissões de conexão com meu perfil AWS fossem estabelecidas.

Também tive que criar uma **key pair** na região `sa-east-1` para que o Terraform pudesse aplicar as configurações para criação da instância EC2, esta que se encontra como `key_name = var.key_name`.

Assim, iniciando o ambiente Terraform no diretório `/infra/terraform` e aplicando as configurações estabelecidas:
```bash
terraform init
terraform apply
```

O ambiente foi devidamente provisionado na AWS:

![](images/terraform-apply-config.png)
![](images/created-instance-after-terraform-apply.png)

O restante das configurações em código do Terraform podem ser acessadas [aqui](https://github.com/CassivsGabriellis/metrics-api-k8s-cluster-performance/tree/main/infra/terraform).

---

## Implementando as configurações com Ansible

Com a infraestrutura provisionada, avancei para a etapa de automação da configuração do nó Kubernetes utilizando Ansible. Minha meta era transformar uma instância recém-criada em um nó Kubernetes funcional, pronto para receber workloads, sem qualquer configuração manual. Estruturei um playbook que executa desde a atualização de pacotes e instalação de dependências base, até a configuração completa do runtime de containers e da própria distribuição k3s. Instalei o Docker para garantir suporte a workloads baseados em containerd e compatibilidade com ferramentas de desenvolvimento, e, em seguida, executei o script oficial de instalação do k3s com opções específicas — incluindo a desativação do Traefik, preservando o cluster limpo para implementações posteriores.

**`playbook.yaml`**:
```
---
- name: Configure EC2 as k3s Kubernetes node
  hosts: k3s_node
  become: true
  vars:
    k3s_version: "" 
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Install base packages
      apt:
        name:
          - curl
          - wget
          - git
        state: present

    - name: Install Docker
      apt:
        name:
          - docker.io
        state: present

    - name: Enable and start Docker
      systemd:
        name: docker
        state: started
        enabled: true

    - name: Add ubuntu user to docker group
      user:
        name: ubuntu
        groups: docker
        append: yes

    - name: Download and install k3s
      shell: |
        curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik" sh -
      args:
        creates: /usr/local/bin/k3s

    - name: Install NGINX Ingress Controller
      become: false
      command: >
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.14.0/deploy/static/provider/cloud/deploy.yaml

    - name: Wait for k3s service to be active
      systemd:
        name: k3s
        state: started
        enabled: true

    - name: Ensure .kube directory exists for ubuntu user
      file:
        path: /home/ubuntu/.kube
        state: directory
        owner: ubuntu
        group: ubuntu
        mode: "0700"

    - name: Copy k3s kubeconfig to ubuntu user
      copy:
        src: /etc/rancher/k3s/k3s.yaml
        dest: /home/ubuntu/.kube/config
        owner: ubuntu
        group: ubuntu
        mode: "0600"
        remote_src: yes
    
    - name: Export KUBECONFIG in ubuntu .bashrc
      lineinfile:
        path: /home/ubuntu/.bashrc
        regexp: '^export KUBECONFIG='
        line: 'export KUBECONFIG=$HOME/.kube/config'
        create: yes
        owner: ubuntu
        group: ubuntu
        mode: "0644"

    - name: Create kubectl symlink for convenience
      file:
        src: /usr/local/bin/kubectl
        dest: /usr/local/bin/k3s-kubectl
        state: link
      ignore_errors: yes

    - name: Ensure kubectl installed (k3s includes it)
      file:
        src: /usr/local/bin/k3s
        dest: /usr/local/bin/kubectl
        state: link
      ignore_errors: yes
```

Junto com as especificações do meu host no arquivo local **`host_vars/k3s-ec2-node.yaml`**:

```
ansible_host: <instance-public-ip>
ansible_user: ubuntu
ansible_ssh_private_key_file: <metrics-api-key.pem-local-address>
```
**`inventory.ini`**:
```
[k3s_node]
k3s-ec2-node
```

Assim, com as configurações dadas, executo o comando para o Ansible aplicá-las:
```
ansible-playbook -i inventory.ini playbook.yaml
```
![](images/ansible-config-success.png)

Após a instalação do k3s via Ansible, mantive a kubeconfig padrão gerada pelo serviço em `/etc/rancher/k3s/k3s.yaml`, sem modificar o endpoint `127.0.0.1:6443`, uma vez que a administração do cluster será realizada diretamente dentro da própria instância EC2, utilizando `kubectl`. Durante a automação, o playbook cuidou da instalação do Docker, da ativação do k3s como serviço, da configuração dos binários e symlinks necessários para o uso do cliente kubectl, garantindo que todos os utilitários essenciais estivessem disponíveis para o usuário padrão da máquina. Ao final dessa etapa, a instância EC2 já operava como um nó Kubernetes funcional, inicializado e pronto para receber aplicações e deployments automatizados via pipeline CI/CD.

Para verificar o estado atual da instância, fiz um acesso via SSH, para averiguar o node sendo executado dentro dela:
![](images/ssh-instance-access.png)

---

## Pipeline CI/CD com GitHub Actions

Com a infraestrutura provisionada e o cluster k3s operacional na EC2, é hora de projetar uma pipeline CI/CD totalmente automatizada usando GitHub Actions. O objetivo é eliminar qualquer necessidade de intervenção manual tanto no build quanto no deploy, garantindo que toda alteração no código da API resulte em uma nova versão do serviço executando no cluster de forma imediata, previsível e confiável.

### Bootstrap do cluster na instância EC2

Antes de continuar com a crição do fluxo CI/CD, é importante notar que a instância encontra-se atualmente sem os objetos Kubernetes na EC2. Se for rodar o comando `kubectl get ns` e `kubectl get all -n metrics-api`, o resultado será que `metrics-api` não aparece na lista de **namespaces** (forma de organizar e isolar recursos dentro de um cluster) e nada existe em `-n metrics-api` (porque o namespace não existe). 

![](images/no-namespace.png)

Dessa forma, é necessário:
* Criar o namespace `metrics-api`;
* Criar o Deployment `metrics-api-deployment`, o Service, e o Ingress.

Para isso, farei uma bootstrap manual na EC2, ou seja, uma inicialização e configuração da instância de forma manual.

1. Copiei os *manifests* Kubernetes da pasta `/k8s` para dentro da EC2 (do seu WSL):

   ```bash
   scp -i ~/.ssh/metrics-api-key.pem -r k8s ubuntu@<public-ip-instance>:/home/ubuntu/k8s
   ```

![](images/scp-to-instance.png)

2. Apois isso, acessei à instância EC2, para verificar se a pasta estava presente:

   ```bash
   ssh -i ~/.ssh/metrics-api-key.pem ubuntu@<public-ip-instance>
   ```

![](images/k8s-inside-instance.png)

3. Apliquei os *manifests* dentro da instância:

   ```bash
   kubectl apply -f /home/ubuntu/k8s/namespace.yaml
   kubectl apply -f /home/ubuntu/k8s/deployment.yaml
   kubectl apply -f /home/ubuntu/k8s/service.yaml
   kubectl apply -f /home/ubuntu/k8s/ingress.yaml
   ```

4. E verifiquei se os *manifests* dentro da instância estão rodando:

   ```bash
   kubectl get ns
   kubectl get deploy -n metrics-api
   kubectl get pods -n metrics-api
   kubectl get svc -n metrics-api
   ```

Desta forma:

* O namespace `metrics-api` existirá
* O `metrics-api-deployment` existirá
* O Service e o Ingress existirão

Assim, na próxima execução do GitHub Actions, o comando:

```sh
kubectl -n metrics-api set image deployment/metrics-api-deployment \
  metrics-api=${IMAGE}
```

vai funcionar, pois as especificações do deployment já existem e só precisam da imagem Docker.

![](images/applied-manifests-inside-instance.png)

Os seguintes `secrets` do Repositório foram estabelecidos para serem chamados no arquivo `ci-cd.yaml`:
![](images/github-repo-secrets.png)

* `DOCKERHUB_USERNAME` - nome de usuário no Docker Hub
* `DOCKERHUB_TOKEN` - token de acesso/senha do Docker Hub
* `EC2_HOST` - IP público da instância (valor `ec2_public_ip` gerado pelo Terraform)
* `EC2_SSH_USER` - escolhi `ubuntu` para AMIs do Ubuntu
* `EC2_SSH_KEY` - conteúdo da chave privada para SSH (arquivo `.pem`)

Esse processo inicial cria a estrutura base do cluster — incluindo o namespace `metrics-api` e os recursos essenciais — permitindo que o pipeline automatizado trabalhe sobre uma fundação já existente. Uma vez que esses objetos iniciais estão aplicados no cluster, todas as atualizações subsequentes podem ser controladas exclusivamente pelo CI/CD, sem necessidade de reaplicar manifests.

Com essa fundação criada, desenvolvi o pipeline do GitHub Actions dividido em duas fases:

1. **Build e Push da imagem Docker:**
   O workflow inicia realizando checkout do repositório e configurando o Docker Buildx. Em seguida, constrói a imagem da API e realiza o push para o Docker Hub utilizando duas tags: `latest`, destinada ao ambiente de desenvolvimento contínuo, e uma tag imutável baseada no SHA do commit, assegurando rastreabilidade e versionamento confiável. Essa abordagem garante que cada build seja reproduzível e associado a um ponto específico da evolução do código.

2. **Deploy automático no cluster k3s:**
   Na segunda etapa, o pipeline estabelece uma conexão SSH com a instância EC2 e utiliza `kubectl set image` para atualizar o Deployment existente com a nova imagem publicada. Como o cluster já possui todos os manifests aplicados no bootstrap inicial, o pipeline precisa apenas ajustar a imagem do Deployment, tornando o processo rápido, eficiente e sem duplicação de recursos. Após a atualização, o workflow aguarda o rollout para confirmar que a nova versão foi aplicada com sucesso.

![](images/github-build-push-deploy.png)

Assim, a pipeline completa — do código à atualização em produção — tornou-se totalmente automatizada, determinística e alinhada às melhores práticas modernas de CI/CD em ambientes Kubernetes.

O código na íntegra da pipeline no GitHub Actions pode ser acesso [aqui](https://github.com/CassivsGabriellis/metrics-api-k8s-cluster-performance/blob/main/.github/workflows/ci-cd.yaml).

### Testes realizados dentro da instância EC2 após deploy

#### Visão geral do node, recursos no namespace da API e listagem dos pods

![](images/after-github-deploy-1.png)

#### Teste nos endpoints da API via `curl` dentro da instância EC2

![](images/after-github-deploy-2.png)

#### Acessando a seção `docs` do FastAPI via IP pública da instância EC2

![](images/docs-fastapi-public-api.png)

---

## Sumário: Acesso à API na EC2 e utilização prática da instância

Com o provisionamento consolidado, a instância EC2 deixa de ser apenas um “nó de infraestrutura” e passa a atuar como ponto de entrada estável para a API de métricas. A seguir, descrevo como ela está exposta, como pode ser consumida externamente e como pode servir de base para extensões futuras do projeto.

### Características da instância e do endpoint público

A instância EC2 foi provisionada como um nó único de Kubernetes com k3s, utilizando o tipo `t3.small`, o que garante 2 vCPUs e 2 GiB de RAM — um equilíbrio melhor entre custo e capacidade para rodar o cluster, o Ingress Controller e a aplicação simultaneamente.

Do ponto de vista de rede, a instância está em:

* Uma VPC dedicada (`10.0.0.0/16`), com:

  * Sub-rede pública (`10.0.1.0/24`) para o nó k3s;
  * Internet Gateway associado à VPC;
  * Tabela de rotas pública com saída `0.0.0.0/0` apontando para o IGW;
* Um Security Group específico para o nó k3s, permitindo:

  * SSH (porta 22) apenas a partir do CIDR definido em `allowed_ssh_cidr`;
  * HTTP (porta 80) aberto para `0.0.0.0/0`, para acesso público à API;
  * HTTPS (porta 443) aberto para futuros cenários com TLS.

Além disso, a instância utiliza um **Elastic IP**, provisionado via Terraform e exposto por meio do output `ec2_public_ip`. Isso garante que:

* O IPv4 público da instância permanece estável entre reinicializações;
* O pipeline CI/CD e quaisquer clientes externos podem apontar para um endereço fixo, sem necessidade de atualizar configurações a cada stop/start.

Na prática, é esse Elastic IP que funciona como “endpoint público bruto” da API.

### Exposição da API via Ingress NGINX

Internamente, o tráfego HTTP é roteado pelo **NGINX Ingress Controller**, instalado no cluster k3s. A topologia lógica fica assim:

```
Cliente → Elastic IP (port 80) → EC2 (Security Group) 
        → ingress-nginx Service LoadBalancer
        → Ingress (rules / path /) 
        → Service ClusterIP (metrics-api-service) 
        → API pod (container FastAPI on the port 8000)
```

O recurso `Ingress` configurado para o namespace `metrics-api` faz o roteamento da raiz `/` para o `metrics-api-service`, que por sua vez encaminha as requisições para o Deployment `metrics-api-deployment`. Isso significa que, externamente, o consumo da API pode ser feito de forma direta, utilizando o Elastic IP na porta 80:

```bash
curl http://<elastic-ip>/health
```

Esse endpoint `/health` é exposto pela aplicação FastAPI e funciona como uma verificação simples de disponibilidade do serviço. Dessa forma, qualquer cliente HTTP — desde scripts de monitoramento até ferramentas de observabilidade — pode utilizar esse endereço para validações básicas ou integrações com sondas de saúde.

### Utilização da instância para inspeção, debug e operação

Além de servir a API externamente, a instância também é o ponto central para operações administrativas e de troubleshooting. A partir de uma sessão SSH utilizando a chave privada (`EC2_SSH_KEY`) e o usuário configurado (`EC2_SSH_USER`, no caso `ubuntu`), é possível:

* Inspecionar o estado do cluster:

  ```bash
  kubectl get nodes -o wide
  kubectl get all -n metrics-api
  ```

* Acompanhar o comportamento dos pods da aplicação:

  ```bash
  kubectl get pods -n metrics-api -o wide
  kubectl logs -n metrics-api <nome-do-pod>
  ```

* Testar a API de dentro do cluster, seja via port-forward, seja executando comandos dentro do pod:

  ```bash
  # Port-forward of the Service to the local machine (inside EC2)
  kubectl port-forward svc/metrics-api-service -n metrics-api 8000:80
  curl http://127.0.0.1:8000/health

  # Direct call from inside the pod
  kubectl exec -it -n metrics-api <pod-name> -- curl -s http://127.0.0.1:8000/health
  ```

Isso transforma a instância em um ponto único de observação do ciclo de vida da aplicação: desde o nível Kubernetes (Deployments, Pods, Services, Ingress) até o nível de aplicação (logs, respostas HTTP, status de saúde).

### Extensões futuras: observabilidade, TLS e domínios customizados

A forma como a instância foi desenhada permite uma série de evoluções naturais, sem necessidade de reestruturar a base:

* **Integração com Prometheus e Grafana:**
  O cluster k3s atual pode receber um stack de observabilidade (como kube-prometheus-stack ou Prometheus Operator) para coletar métricas tanto da infraestrutura quanto da API. O Ingress Controller já oferece um ponto de entrada HTTP que pode ser reutilizado para expor dashboards ou endpoints de métricas.

* **TLS e domínio customizado (HTTPS):**
  Como a API já está exposta por um Elastic IP, é simples criar um registro DNS em um domínio próprio (via Route 53 ou outro provedor) apontando para esse IP. Em seguida, basta adicionar um novo Ingress com host definido (por exemplo, `api.metrics.meudominio.com`) e integrar um emissor de certificados (como AWS Certificate Manager ou Let's Encrypt) para servir tráfego HTTPS.

* **Ampliação do cluster e novos serviços:**
  A instância atual pode ser o ponto de partida para hospedar outros microservices relacionados a métricas, dashboards ou APIs auxiliares. Novos namespaces, Deployments e Services podem ser adicionados ao cluster, todos expostos via NGINX Ingress Controller com regras específicas de rota e host.

Em resumo, a instância EC2 — combinada com k3s, Ingress NGINX, Docker e a pipeline CI/CD no GitHub Actions — passa a operar como um ambiente de aplicação completo, apto não apenas para servir a API de métricas em produção, mas também para suportar testes, experimentos e futuras extensões em termos de observabilidade, segurança (TLS) e escalabilidade lógica da solução.