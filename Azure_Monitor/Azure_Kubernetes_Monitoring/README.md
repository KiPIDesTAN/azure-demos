# Azure Kubernetes Monitoring

This area contains information about spinning up an AKS cluster and monitoring it with Container Insights and Managed Prometheus. The primary purpose is to document the bicep commands to associate the appropriate functionality with the AKS instance.

There are two separate demos.

1. [AKS - Public](./AKS_Public/) - This will deploy AKS with Container Insights and Managed Prometheus DCRs that utilized public end points.
2. [AKS - Private](./AKS_AMPLS/) - This will deploy AKS with Container Insights and Managed Prometheus DCRs that utilize Azure Monitor Private Link Scope to force network isolation on all monitoring communications

## Additional References

I wrote documentation comparing the various AKS monitoring options at [Azure AKS Observability Options](https://kipidestan.github.io/Azure-AKS-Observability-Options/). 