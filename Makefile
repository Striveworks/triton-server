
REGISTRY=724664234782.dkr.ecr.us-east-1.amazonaws.com/library/hardened
DATE=$(shell date '+%Y-%m-%d')
TRITONSERVER_VERSION=24.09-py3
tritonserver-cpu:
	docker buildx build --platform linux/amd64 --progress=plain -o type=docker -t $(REGISTRY)/library/hardened/nvidia/tritonserver:$(TRITONSERVER_VERSION)-$(DATE) -f Dockerfile.rocky-cpu .

tritonserver-gpu:
	docker buildx build --platform linux/amd64 --progress=plain -o type=docker -t $(REGISTRY)/library/hardened/nvidia/tritonserver:$(TRITONSERVER_VERSION)-$(DATE) -f Dockerfile.rocky-gpu .