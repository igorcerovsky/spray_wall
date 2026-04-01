# Spray Wall Vector Model System

## Design Specification v1.0

Author: <your name>
Date: 2026
Status: Initial Full Design

---

# 1. System Goals

This system models a real climbing spray wall as a structured,
vector-based environment supporting:

* Accurate wall geometry
* Hand holds and footholds
* Directional grip vectors
* Route creation
* Attempt recording
* Reach-based modelling
* Kid route generation
* Future machine learning route generation

The wall is static (holds do not move), but new holds may be added.

The long-term objective is to create a **digital twin** of the physical climbing wall.

---

# 2. Physical Wall Specification

## 2.1 Main Wall

Width: **360 cm**
Height: **320 cm**
Angle: **45° overhang**

---

## 2.2 Kickboard

Width: **360 cm**
Height: **40 cm**
Angle: **0° (vertical)**

---

## 2.3 Total System Height

Kickboard range:

0–40 cm

Main wall range:

40–360 cm

---

## 2.4 Coordinate Origin

Defined as:

Bottom-left corner of kickboard.

---

# 3. Coordinate System

All positions stored in:

Units: **centimeters**

Axes:

X → right
Y → up

Example:

```
Hold at:
x = 180
y = 245
```

Meaning:

180 cm from left
245 cm from floor.

---

# 4. Image Rectification

## 4.1 Input

Single iPhone photograph of the wall.

Camera recommendations:

* Centered
* Perpendicular to wall
* Good lighting
* All corners visible

---

## 4.2 Reference Points

User marks:

Kickboard:

* bottom-left
* bottom-right
* top-left
* top-right

Main wall:

* bottom-left
* bottom-right
* top-left
* top-right

Total:

**8 reference points**

---

## 4.3 Output

Generated files:

```
main_wall_rectified.png
kickboard_rectified.png
```

Pixel scale target:

```
1 pixel = 0.5 cm
```

---

# 5. Hold Model

## 5.1 Hold Types

Defined roles:

```
hand
foot
micro_foot
```

---

## 5.2 Special Flags

Holds may include:

```
start
top
start_foot
```

---

## 5.3 Hold Object

```json
{
  "id": 42,

  "x_cm": 142,
  "y_cm": 235,

  "plane": "main",

  "role": "hand",

  "flags": {
    "start": false,
    "top": false,
    "start_foot": false
  },

  "grips": []
}
```

---

# 6. Grip Model

Each hold contains:

```
1–3 grips typical
1 grip for micro footholds
```

---

## 6.1 Grip Object

```json
{
  "id": 1,

  "angle_deg": 210,

  "strength": 0.6,

  "precision": 0.2
}
```

---

## 6.2 Strength Definition

Normalized scale:

```
0.0 → unusable
0.2 → poor sloper
0.5 → average hold
0.8 → good hold
1.0 → perfect jug
```

---

## 6.3 Precision Definition

Represents placement difficulty.

Typical:

```
Hand holds → 0.1–0.3
Foot holds → 0.3–0.6
Micro footholds → 0.6–1.0
```

---

# 7. Visual Representation

Supports **color-blind-safe symbols**.

---

## 7.1 Hold Shapes

Hand hold:

```
Circle
```

Start hold:

```
Rectangle rotated 90°
```

Top hold:

```
Rectangle
```

Foot hold:

```
Triangle
```

Micro foothold:

```
Small filled circle
```

---

## 7.2 Colors

Default:

```
Start → Green
Top → Red
Hand → Blue
Foot → Yellow
```

Color-blind mode:

Uses shapes only.

---

# 8. Route Model

Expected total:

```
500+ routes
```

Display:

```
One route at a time
```

---

## 8.1 Route Object

```json
{
  "id": 12,

  "name": "Warmup 1",

  "start_holds": [1, 2],

  "start_feet": [301],

  "sequence": [
    12,
    44,
    78,
    91
  ],

  "top_holds": [199],

  "top_mode": "match"
}
```

---

## 8.2 Top Modes

Supported:

```
match
touch
```

---

# 9. Attempt Recording

Each climbing attempt is logged.

---

## 9.1 Attempt Object

```json
{
  "id": 1021,

  "route_id": 12,

  "date": "2026-03-14",

  "climber_id": 1,

  "result": "success",

  "notes": "Fell once before sending"
}
```

---

# 10. Climber Model

Used for reach modelling.

---

## 10.1 Climber Object

```json
{
  "id": 1,

  "name": "Child A",

  "height_cm": 135,

  "wingspan_cm": 130,

  "strength_factor": 0.6
}
```

---

# 11. Reach Model (Future Phase)

Uses:

* Grip position
* Grip direction
* Grip strength
* Wall angle
* Climber wingspan

Outputs:

```
Reachable holds
Move feasibility
Route difficulty estimate
```

---

# 12. Machine Learning Goals (Future)

Activated after sufficient dataset growth.

Target models:

```
Difficulty prediction
Route generation
Movement feasibility
```

Training sources:

```
Routes
Attempts
Climber data
```

---

# 13. Data Storage Layout

```
wall_project/

  photo_original.jpg

  main_wall_rectified.png
  kickboard_rectified.png

  wall_geometry.json

  holds.json
  routes.json
  attempts.json
  climbers.json
```

---

# 14. Performance Targets

System capacity:

```
400–500 holds
500–650 grips
500+ routes
```

Rendering target:

```
60 FPS
```

---

# 15. UI Screens

## 15.1 Wall Calibration

Steps:

* Load photo
* Mark 8 reference points
* Enter dimensions

Output:

Rectified wall.

---

## 15.2 Hold Editor

Interactions:

```
Tap → add hold
Drag → move hold
Long press → delete hold
```

Toggle type:

```
Hand
Foot
Micro foot
```

---

## 15.3 Grip Editor

Available actions:

```
Add arrow
Rotate arrow
Adjust strength
Adjust precision
Delete grip
```

---

## 15.4 Route Editor

Workflow:

```
Set start holds
Set start feet
Add move sequence
Set top holds
```

---

## 15.5 Attempt Logger

User:

```
Select route
Record success or failure
Add optional notes
```

---

# 16. Versioning Strategy

Rules:

```
Hold IDs never reused
New holds appended only
Routes reference Hold IDs
```

---

# 17. Future Expansion Goals

Planned:

```
Difficulty prediction
Kid-friendly route generation
Dynamic reach simulation
ML-based route creation
Movement animation
Video overlay analysis
```

---

# 18. System Risks

Primary risks:

```
1. Poor photo rectification
2. Incorrect coordinate scaling
3. Excessive UI complexity
```

Mitigation:

```
Structured calibration workflow
Incremental feature rollout
```

---

# 19. Validation Metrics

System success measured by:

```
Accurate hold placement
Reliable route creation
Correct attempt logging
Reach model consistency
Performance stability
```

---
