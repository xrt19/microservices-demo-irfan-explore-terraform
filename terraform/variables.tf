# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

variable "gcp_project_id" {
  type        = string
  description = "The GCP project ID to apply this config to"
}

variable "name" {
  type        = string
  description = "Name given to the new GKE cluster"
  default     = "online-boutique-irfan"
}

variable "region" {
  type        = string
  description = "Region of the new GKE cluster"
  default     = "asia-southeast2"
}

variable "namespace" {
  type        = string
  description = "Kubernetes Namespace in which the Online Boutique resources are to be deployed"
  default     = "default"
}

variable "filepath_manifest" {
  type        = string
  description = "Path to Online Boutique's Kubernetes resources, written using Kustomize"
  default     = "../kustomize/"
}

variable "machine_type" {
  type        = string
  description = "Machine type for GKE nodes"
  default     = "e2-custom-4-6144"
}

variable "node_count_per_zone" {
  type        = number
  description = "Number of nodes per zone (3 zones in asia-southeast2 = total nodes × 3)"
  default     = 1
}

variable "min_node_count_per_zone" {
  type        = number
  description = "Minimum number of nodes per zone for autoscaling"
  default     = 1
}

variable "max_node_count_per_zone" {
  type        = number
  description = "Maximum number of nodes per zone for autoscaling"
  default     = 2
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size in GB for GKE nodes"
  default     = 30
}

variable "disk_type" {
  type        = string
  description = "Boot disk type for GKE nodes"
  default     = "pd-standard"
}

variable "image_type" {
  type        = string
  description = "Node image type for GKE nodes"
  default     = "COS_CONTAINERD"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for GKE cluster and nodes"
  default     = "1.32"
}

variable "memorystore" {
  type        = bool
  description = "If true, Online Boutique's in-cluster Redis cache will be replaced with a Google Cloud Memorystore Redis cache"
}
