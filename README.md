# A Resilient Cloud-Edge Digital Twin Framework for Urban UAV Logistics

This repository contains the official implementation and simulation environment for the research paper: **"A Resilient Cloud-Edge Digital Twin Framework for Urban UAV Logistics Under 3D Blockages and ADS-B Spoofing"**.

## 1. Overview
[cite_start]This framework addresses critical operational bottlenecks in urban low-altitude Unmanned Aerial Vehicle (UAV) networks, specifically focusing on complex 3D spatial blockages and information-layer threats such as ADS-B spoofing[cite: 14, 15]. The proposed architecture operates through a dual-tier "Teacher-Student" paradigm:

* [cite_start]**Cloud Digital Twin (Teacher):** Manages macroscopic routing and global trajectory refinement using Conditional Diffusion Models[cite: 16, 17].
* [cite_start]**Edge Digital Twin (Student):** Assumes control during ADS-B spoofing attacks, utilizing progressive distillation for rapid, one-step emergency inference[cite: 20, 21].
* [cite_start]**Security Mechanism:** A distributed Time Difference of Arrival (TDOA) anchor network for real-time coordinate validation and authority handoff[cite: 18, 19].

## 2. Requirements

### Python Environment
* Python 3.8+
* PyTorch (for diffusion models and inpainting)
* NumPy & SciPy (for data processing)
* Matplotlib (for 2D visualization)

### MATLAB Environment
* MATLAB R2022a or later
* Statistics and Machine Learning Toolbox (for DBSCAN)

## 3. Repository Structure

### Environment Initialization
* [cite_start]`City_Topology_Init.m`: Generates the 3D urban environment, heterogeneous user clusters, and the communication penalty heatmap based on ITU-R P.526[cite: 155].

### Core Algorithms (Python)
* `diffusion_trajectory.py`: Implements the macro-scale trajectory optimization using generative noise reduction.
* `3D_trajectory.py`: Extends the optimization to three-dimensional space with node-driven altitude control.
* `crisis_reaction.py`: Simulates the TDOA alarm trigger and Edge DT evasive maneuvers via trajectory inpainting.

### Visualization & Analysis (MATLAB)
* `threeD_trajectory.m`: Renders the high-definition 3D flight profiles and urban architecture.
* `Plot_Fig1_Survival.m`: Generates the UAV survival rate analysis under varying attack intensities.
* `Plot_Fig3_Macro.m`: Visualizes the global logistics hubs and optimized trajectories.
* `kuosan.m`: Analyzes the convergence performance of the proposed diffusion model compared to PSO and DRL baselines.

