# Photo Upload Helm Chart

This Helm chart deploys the Photo Upload application with both backend (Java/Spring Boot) and frontend (React/Nginx) components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- An existing MariaDB database
- Traefik or another ingress controller installed

## Installing the Chart

To install the chart with the release name `photo-upload`:

```bash
helm install photo-upload ./helm/photo-upload
```

### Custom Values

You can customize the installation by providing your own values:

```bash
helm install photo-upload ./helm/photo-upload \
  --set database.external.host=your-mariadb-host \
  --set database.external.password=your-secure-password \
  --set ingress.hosts[0].host=your-domain.com
```

Or create a `custom-values.yaml` file:

```yaml
database:
  external:
    host: mariadb.database.svc.cluster.local
    password: secure-password

ingress:
  hosts:
    - host: photo-upload.example.com
      paths:
        - path: /api
          pathType: Prefix
          backend: api
        - path: /swagger-ui
          pathType: Prefix
          backend: api
        - path: /v3/api-docs
          pathType: Prefix
          backend: api
        - path: /
          pathType: Prefix
          backend: web

backend:
  image:
    repository: your-registry/photo-upload-backend
    tag: "1.0.0"

frontend:
  image:
    repository: your-registry/photo-upload-frontend
    tag: "1.0.0"
```

Then install with:

```bash
helm install photo-upload ./helm/photo-upload -f custom-values.yaml
```

## Configuration

The following table lists the configurable parameters of the Photo Upload chart and their default values.

### Global Parameters

| Parameter      | Description                        | Default |
| -------------- | ---------------------------------- | ------- |
| `replicaCount` | Number of replicas for deployments | `1`     |

### Backend Parameters

| Parameter                          | Description                           | Default                |
| ---------------------------------- | ------------------------------------- | ---------------------- |
| `backend.image.repository`         | Backend image repository              | `photo-upload-backend` |
| `backend.image.tag`                | Backend image tag                     | `latest`               |
| `backend.image.pullPolicy`         | Image pull policy                     | `IfNotPresent`         |
| `backend.service.type`             | Kubernetes service type               | `ClusterIP`            |
| `backend.service.port`             | Service port                          | `8080`                 |
| `backend.javaOpts`                 | Java JVM options                      | `-Xmx768m -Xms512m`    |
| `backend.persistence.enabled`      | Enable persistent storage for uploads | `true`                 |
| `backend.persistence.size`         | Persistent volume size                | `10Gi`                 |
| `backend.persistence.storageClass` | Storage class name                    | `""`                   |

### Frontend Parameters

| Parameter                   | Description               | Default                 |
| --------------------------- | ------------------------- | ----------------------- |
| `frontend.image.repository` | Frontend image repository | `photo-upload-frontend` |
| `frontend.image.tag`        | Frontend image tag        | `latest`                |
| `frontend.image.pullPolicy` | Image pull policy         | `IfNotPresent`          |
| `frontend.service.type`     | Kubernetes service type   | `ClusterIP`             |
| `frontend.service.port`     | Service port              | `80`                    |

### Database Parameters

| Parameter                    | Description           | Default       |
| ---------------------------- | --------------------- | ------------- |
| `database.external.enabled`  | Use external database | `true`        |
| `database.external.host`     | Database host         | `mariadb`     |
| `database.external.port`     | Database port         | `3306`        |
| `database.external.name`     | Database name         | `photoupload` |
| `database.external.user`     | Database user         | `photoupload` |
| `database.external.password` | Database password     | `photoupload` |

### Ingress Parameters

| Parameter           | Description                 | Default         |
| ------------------- | --------------------------- | --------------- |
| `ingress.enabled`   | Enable ingress              | `true`          |
| `ingress.className` | Ingress class name          | `traefik`       |
| `ingress.hosts`     | Ingress hosts configuration | See values.yaml |

## Uninstalling the Chart

To uninstall/delete the `photo-upload` deployment:

```bash
helm uninstall photo-upload
```

## Upgrading the Chart

To upgrade the `photo-upload` deployment:

```bash
helm upgrade photo-upload ./helm/photo-upload
```

## Using with Traefik

This chart is configured to work with Traefik out of the box. The ingress template includes Traefik-specific annotations:

```yaml
ingress:
  className: "traefik"
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
```

## Health Checks

The backend includes health check endpoints:

- Liveness probe: `GET /actuator/health`
- Readiness probe: `GET /actuator/health`

The frontend includes basic HTTP checks on the root path.

## Persistent Storage

The backend requires persistent storage for uploaded photos. By default, a PersistentVolumeClaim is created with 10Gi storage. You can customize this in the values:

```yaml
backend:
  persistence:
    enabled: true
    size: 50Gi
    storageClass: "fast-ssd"
```

## Security

The chart includes security best practices:

- Non-root user execution (UID 10001)
- Security contexts configured
- Service account with minimal permissions
- Secrets for sensitive database credentials

## Troubleshooting

### Check pod status

```bash
kubectl get pods -l app.kubernetes.io/name=photo-upload
```

### View logs

```bash
kubectl logs -l app.kubernetes.io/name=photo-upload-backend
kubectl logs -l app.kubernetes.io/name=photo-upload-frontend
```

### Test database connectivity

```bash
kubectl exec -it <backend-pod> -- env | grep MARIADB
```

### Check ingress

```bash
kubectl get ingress
kubectl describe ingress photo-upload
```
