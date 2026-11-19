# Template for ANY language: keep the first block (AWS CLI + wrapper), change the middle.
FROM python:3.12-slim

# --- platform part: same in every image ---
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip ca-certificates \
 && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip \
 && unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install \
 && rm -rf /tmp/aws /tmp/awscli.zip /var/lib/apt/lists/*
COPY --from=wrapper exp-wrapper.sh /usr/local/bin/exp-wrapper
RUN chmod +x /usr/local/bin/exp-wrapper

# --- your part: install your language's dependencies and copy your code ---
WORKDIR /app
COPY main.py .

ENTRYPOINT ["/usr/local/bin/exp-wrapper"]
CMD ["python", "main.py", "20"]
