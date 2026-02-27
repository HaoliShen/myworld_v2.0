# Entity Architecture Reference

The project follows a **Composition over Inheritance** pattern. Entities are built by composing specialized components rather than deep inheritance trees.

## Core Concepts

-   **Entities**: The main game objects (Player, NPC, Trees, etc.).
-   **Components**: Reusable `Node` or `Node2D` that provide specific functionality (Health, Interaction, Animation).
-   **Controllers**: Specialized components that manage complex logic (Movement, AI).

## Standard Node Structure

### 1. Actor Entity (Player / NPC)

Base Class: `CharacterBody2D`

```
root (CharacterBody2D) - script: Player.gd / HumanNPC.gd
├── Visuals (Node2D)
│   ├── Body (AnimatedSprite2D)
│   ├── Shadow (Sprite2D)
│   └── SelectionMarker (Sprite2D)
├── CollisionShape2D
├── Components (Node)
│   ├── MovementController (Node) - Handles physics & navigation
│   ├── InteractionController (Node) - Handles initiating interactions
│   ├── AnimationController (Node) - Handles state-based animations
│   ├── HealthComponent (Node) - Handles health & death
│   └── NPCBrain (Node) - [NPC Only] Handles AI state machine
└── CameraRig (Node2D) - [Player Only]
```

### 2. Static Object Entity (Tree / Rock)

Base Class: `Node2D` or `StaticBody2D`

```
root (Node2D/StaticBody2D) - script: TreeEntity.gd
├── Visuals (Node2D)
│   ├── Sprite (Sprite2D)
│   └── Shadow (Sprite2D)
├── CollisionShape2D (if blocking)
├── Components (Node)
│   ├── InteractableComponent (Node) - Handles receiving interactions (e.g., "chop")
│   ├── HealthComponent (Node) - Handles durability & destruction
│   └── AnimationController (Node) - Handles hit/die animations
```

## Component Reference

### HealthComponent
-   **Path**: `Scripts/components/entity/HealthComponent.gd`
-   **Purpose**: Manages current/max health.
-   **Signals**: `died`, `health_changed`, `damaged`.

### InteractionController (Actor)
-   **Path**: `Scripts/components/interaction/InteractionController.gd`
-   **Purpose**: Detects `InteractableComponent` areas and initiates interaction.
-   **Usage**: Add child nodes for specific behaviors (e.g., `ChopBehavior`, `TalkBehavior`).

### InteractableComponent (Object)
-   **Path**: `Scripts/components/interaction/InteractableComponent.gd`
-   **Purpose**: Defines an area that can be interacted with.
-   **Properties**: `interaction_label` (e.g., "chop", "talk").

### AnimationController
-   **Path**: `Scripts/components/animation/AnimationController.gd`
-   **Purpose**: State machine for playing animations based on logic nodes.
