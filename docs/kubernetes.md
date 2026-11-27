# Kubernetes (Lab 8) / Kubernetes (Упражнение 8)

The notes app runs in a Kubernetes cluster made with **kind**, together with PostgreSQL, using the image from GHCR (Lab 6).
Everything the cluster runs is described in Git, in the `k8s/` folder.

| File | What is inside |
|---|---|
| `k8s/app.yaml` | ConfigMap `app-config` (`APP_VERSION`), Deployment `notes` (4 pods, image `v0.6.0`, readiness and liveness probes), Service `notes` (port 8000) |
| `k8s/db.yaml` | Secret `db-secret`, PersistentVolumeClaim `db-data` (1Gi), Deployment `db` (`postgres:17-alpine`, strategy `Recreate`), Service `db` (port 5432) |

## Run it / Стартиране

In a Codespace of this repository:

```bash
# once: kind, kubectl and a cluster
A=$(dpkg --print-architecture)
curl -fsSLo /tmp/kind https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-$A
curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/$A/kubectl"
sudo install /tmp/kind /tmp/kubectl /usr/local/bin/
kind create cluster --name lab
kubectl get nodes

# the image from Lab 6 (names in lowercase)
IMAGE=ghcr.io/polyma-29/devops-labs-fn373223046
docker pull $IMAGE:v0.6.0
kind load docker-image $IMAGE:v0.6.0 --name lab

# the database and the app
kubectl apply -f k8s/db.yaml -f k8s/app.yaml
kubectl rollout status deployment/db
kubectl rollout status deployment/notes
kubectl get pods,pvc

# from outside: a tunnel to the Service
kubectl port-forward service/notes 8080:8000 &
curl localhost:8080/version          # {"version":"0.8.0"}
curl -X POST localhost:8080/notes -H "Content-Type: application/json" -d '{"title": "First note"}'
curl localhost:8080/notes
```

After a rollout, start `kubectl port-forward` again: it is connected to one pod, and that pod is gone.

Remove everything: `kind delete cluster --name lab`.

## What we did and saw / Какво направихме

The output below is from a real run on kind (Kubernetes v1.37.0) on 27.11.2026. Long lines are shortened.

### A. What an orchestrator does that Compose does not

Compose starts containers on one machine and stops there. If a container dies or the machine is lost, nobody fixes it.

Kubernetes keeps a **desired state**: "I want 4 copies of this image, reachable under this name". It compares this with reality all the time and fixes the difference by itself:

- a pod dies or is deleted: a new one is made (part B);
- more copies with `kubectl scale`, and one stable name that spreads requests across them: Service (part C);
- settings and passwords outside the image: ConfigMap and Secret; data that lives longer than a pod: PersistentVolumeClaim (part D);
- a new version pod by pod, without downtime, and a way back: rolling update and `kubectl rollout undo` (part E);
- probes: requests go only to pods that are ready, and a stuck container is restarted (parts D and F);
- many machines (nodes): Kubernetes chooses where each pod runs. We have one node.

### B. A bare pod and a Deployment

A bare pod runs, but when it is deleted, nothing brings it back:

```text
$ kubectl run hello --image=nginx:alpine
pod/hello created
$ kubectl delete pod hello
pod "hello" deleted from default namespace
$ kubectl get pods
No resources found in default namespace.
```

The Deployment wants 2 pods. When one is deleted, its ReplicaSet makes a new one (new name `...-b6sng` instead of `...-44mk8`):

```text
$ kubectl delete pod notes-674c8bcd58-44mk8
pod "notes-674c8bcd58-44mk8" deleted from default namespace
$ kubectl get pods
NAME                     READY   STATUS    RESTARTS   AGE
notes-674c8bcd58-b6sng   1/1     Running   0          31s
notes-674c8bcd58-ssk5x   1/1     Running   0          32s
```

### C. A Service, and why the note is there only sometimes

```text
$ kubectl get services
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP    103s
notes        ClusterIP   10.96.166.226   <none>        8000/TCP   1s
$ kubectl run tmp --rm -i --restart=Never --image=busybox -- wget -qO- http://notes:8000/version
{"version":"0.1.0"}
```

`0.1.0` is the app's default: `APP_VERSION` is not set yet. One note was created from outside (through `port-forward`), then 6 requests were sent from inside:

```text
$ kubectl run tmp --rm -i --restart=Never --image=busybox -- \
    sh -c 'for i in 1 2 3 4 5 6; do wget -qO- http://notes:8000/notes; echo; done'
[{"id":1,"title":"First note","body":"from outside","category":null}]
[]
[]
[{"id":1,"title":"First note","body":"from outside","category":null}]
[]
[]
```

**Why is the note there sometimes and sometimes not?** The Service spreads the requests across the two pods. Without `DATABASE_URL` each pod keeps the notes in its own memory, so the note exists only in the pod that created it. `port-forward` always goes to one pod, so from outside the answer never changes (here it was the pod with the note).

### D. Database, settings and secrets

```text
$ kubectl apply -f k8s/db.yaml -f k8s/app.yaml
secret/db-secret created
persistentvolumeclaim/db-data created
deployment.apps/db created
service/db created
configmap/app-config created
deployment.apps/notes configured
service/notes unchanged
$ kubectl get pods,pvc
NAME                         READY   STATUS        RESTARTS   AGE
pod/db-5679c76d64-mtddk      1/1     Running       0          27s
pod/notes-674c8bcd58-bhqjg   1/1     Terminating   0          94s
pod/notes-864f8f8d68-mb9r6   1/1     Running       0          6s
pod/notes-864f8f8d68-v6hbd   1/1     Running       0          27s

NAME                            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
persistentvolumeclaim/db-data   Bound    pvc-cbf57f84-2192-440b-acfb-a6439c9c653c   1Gi        RWO            standard
$ curl localhost:8080/version
{"version":"0.8.0"}
```

`0.8.0` now comes from the ConfigMap.

**1. Create a note and send the 6 requests again. Is it always there now?**
Yes, 6 of 6 requests return it. Both pods keep the notes in the same Postgres (through the Service `db`), so they see the same data.

```text
[{"id":1,"title":"Stored in Postgres","body":"Lab 8","category":null}]   (6 times)
```

**2. Delete the database pod. Did the note survive? What keeps it?**
Yes. The Deployment `db` made a new pod, and the new pod mounted the same PersistentVolumeClaim `db-data` (the same volume `pvc-cbf57f84-...`). Postgres keeps its files on that disk (`/var/lib/postgresql/data`). The pod is temporary, the disk is not. (For updates, `strategy: Recreate` stops the old Postgres pod before a new one starts, so two Postgres servers never use the same disk.)

```text
$ kubectl delete pod -l app=db
pod "db-5679c76d64-mtddk" deleted from default namespace
$ kubectl rollout status deployment/db
deployment "db" successfully rolled out
$ curl localhost:8080/notes
[{"id":1,"title":"Stored in Postgres","body":"Lab 8","category":null}]
```

**3. Change the version with `kubectl patch`. What does `/version` show?**
Still `0.8.0`, on every pod. The pods read environment variables only when the container starts, so a change in the ConfigMap does not reach pods that already run. After `kubectl rollout restart deployment/notes` the new pods show `0.8.1`.

```text
$ kubectl patch configmap app-config -p '{"data":{"APP_VERSION":"0.8.1"}}'
configmap/app-config patched
$ curl localhost:8080/version
{"version":"0.8.0"}
$ kubectl rollout restart deployment/notes
deployment.apps/notes restarted
$ curl localhost:8080/version
{"version":"0.8.1"}
```

Git still says `0.8.0`, so after this test `k8s/app.yaml` was applied again and the pods were restarted: the cluster matches Git again.

**4. The password is in base64. Is that encryption?**
No. base64 is only an encoding, and anyone can decode it without a key:

```text
$ kubectl get secret db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
change-me
```

Anyone who can read Secrets in the cluster (or a backup of etcd) can read the password. Here it is also in Git as plain text (`k8s/db.yaml`), which is fine only for a lab. In a real project: keep the password out of Git (create the Secret with `kubectl create secret`, or use Sealed Secrets, SOPS or an external secret store), turn on encryption at rest for etcd, and allow only a few users to read Secrets (RBAC).

### E. Scaling, rolling update and rollback

```text
$ kubectl scale deployment notes --replicas=4
deployment.apps/notes scaled
$ TAG=$(git rev-parse origin/main)
$ docker pull $IMAGE:$TAG && kind load docker-image $IMAGE:$TAG --name lab
$ kubectl set image deployment/notes notes=$IMAGE:$TAG
deployment.apps/notes image updated
$ kubectl rollout status deployment/notes
deployment "notes" successfully rolled out
$ kubectl annotate deployment/notes kubernetes.io/change-cause="image $TAG (main)"
$ kubectl rollout history deployment/notes
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
3         <none>
4         <none>
5         image e7d8a6739b4acea3e867c4e8dfa4a6eaf30d76f4 (main)
$ kubectl rollout undo deployment/notes
deployment.apps/notes rolled back
$ kubectl get deployment notes -o wide
NAME    READY   UP-TO-DATE   AVAILABLE   CONTAINERS   IMAGES
notes   4/4     4            4           notes        ghcr.io/polyma-29/devops-labs-fn373223046:v0.6.0
```

**Watch: how many pods are serving at the worst moment?**
**3 of 4.** During the update the ready endpoints of the Service were counted about twice a second: never fewer than 3, never more than 4. By default a rolling update may have 25% of the pods unavailable (1 of 4) and 25% extra (1 more). So Kubernetes stops 1 old pod at once and starts 2 new ones; every next old pod stops only after a new pod passes its readiness probe. From `kubectl get pods -w`:

```text
notes-7c5db46c8d-92n46   0/1     Pending       0          0s    <- 2 new pods start
notes-7fcf746c77-b4pzr   1/1     Terminating   0          14s   <- 1 old pod may stop at once (25% of 4)
notes-7c5db46c8d-kh2p2   0/1     Pending       0          0s
notes-7c5db46c8d-kh2p2   1/1     Running       0          3s    <- a new pod is ready...
notes-7fcf746c77-fbjll   1/1     Terminating   0          17s   <- ...only then the next old pod stops
```

**Compare with the Compose rollback from Lab 6:** `docker compose up -d` with another `APP_TAG` stops the only app container and then starts the new one, so for a few seconds **0** containers serve (downtime). Kubernetes never went below 3 serving pods, and the rollback (`rollout undo`) is also a rolling update.

One more thing we saw: a request was sent from inside every 0.2 s during the update, and 3 of 95 failed. In two more tests with `kubectl rollout restart`, 2 of 150 and 4 of 93 failed, with `Connection refused` or `download timed out`. An old pod stops listening a moment before the Service stops sending requests to it. With a `preStop` hook (`sleep 5`) in the container, two more tests had 0 failed requests (127 of 127 and 167 of 167 OK). The lab manifests do not have this hook; it is a good next step.

**Git describes what is running.** `kubectl scale` and `kubectl set image` change the cluster, not the file, so `replicas: 4` is now in `k8s/app.yaml`. After `rollout undo` the image is `v0.6.0` again, as in the file. At the end the cluster and Git are the same:

```text
$ kubectl diff -f k8s/; echo $?
0
```

### F. Fix the broken ones

Each break was made on purpose and then fixed. The fix is always "back to what Git describes": `kubectl apply -f k8s/...` or `kubectl rollout undo`.

| # | The break | `kubectl get pods` shows | Command that shows the cause | What it says | Fix |
|---|---|---|---|---|---|
| 1 | `kubectl set image deployment/notes notes=$IMAGE:v9.9.9` | 2 new pods `ImagePullBackOff`; 3 old pods `1/1 Running` keep serving | `kubectl describe pod <new pod>` (Events) | `Failed to pull image ".../devops-labs-fn373223046:v9.9.9": ... not found` | `kubectl rollout undo deployment/notes` |
| 2 | readiness probe on `/readyz` | new pods `Running` but `0/1`; `rollout status` stops at "2 out of 4 new replicas have been updated" | `kubectl describe pod <new pod>` | `Readiness probe failed: HTTP probe failed with statuscode: 404` | path `/ready`: `kubectl apply -f k8s/app.yaml` |
| 3 | Service `selector: app: note` | all pods `1/1 Running` (healthy) | `kubectl get endpointslices -l kubernetes.io/service-name=notes`, then `kubectl describe service notes` | endpoints `<unset>`; `Selector: app=note`, but the pods have `app=notes`; wget: `can't connect to remote host (10.96.166.226): Connection refused` | selector `app: notes`: `kubectl apply -f k8s/app.yaml` |
| 4 | `kubectl delete secret db-secret`, then `kubectl rollout restart deployment/notes` | new pods `CreateContainerConfigError`; old pods still `Running` | `kubectl describe pod <new pod>` | `Error: secret "db-secret" not found` | `kubectl apply -f k8s/db.yaml` creates the Secret again; the kubelet retries by itself |
| 5 | liveness probe on port 9000 | first all `1/1 Running` (readiness on 8000 passes, so the rollout replaces all pods); after 83 s `RESTARTS 2 (23s ago)` | `kubectl describe pod <pod>` | `Liveness probe failed: Get "http://10.244.0.49:9000/health": ... connection refused`, `Container notes failed liveness probe, will be restarted` | port 8000: `kubectl apply -f k8s/app.yaml` |

How to find a problem: `kubectl get pods` shows the symptom; `kubectl describe pod` (the Events at the end) shows why a pod cannot start or is not ready; `kubectl get endpointslices` shows whether a Service finds any pods; `kubectl logs` helps when the app itself crashes. In breaks 1 and 4 the container never started, so there were no logs.

## What is next

Not in this lab: Ingress (HTTP access from outside by name), Helm, a StatefulSet for the database, HorizontalPodAutoscaler, namespaces and RBAC, GitOps (Argo CD), managed clusters (EKS, GKE, AKS).
