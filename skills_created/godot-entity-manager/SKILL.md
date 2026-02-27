---
name: godot-entity-manager
description: Manage Godot game entities (Player, NPC, Objects) following the project's composition-based architecture. Use this skill when creating new entities, adding components to existing ones, or checking architectural compliance.
---

# Godot Entity Manager

This skill enforces the project's **Composition over Inheritance** architecture for game entities.

## When to Use

-   **Creating New Entities**: When adding a new NPC, enemy, or interactive object.
-   **Refactoring**: When cleaning up old entity code to match the standard.
-   **Adding Features**: When adding health, interaction, or movement capabilities to an entity.

## Entity Architecture

The project uses a component-based design where entities are composed of reusable `Node` logic rather than deep inheritance.

**Key Reference**: See [entity_architecture.md](references/entity_architecture.md) for detailed node structures and component definitions.

## Workflows

### 1. Creating a New Actor (NPC/Enemy)

1.  **Create Scene**: Inherit from `CharacterBody2D`.
2.  **Add Visuals**: Create a `Visuals` Node2D with sprites/animations.
3.  **Add Components**: Create a `Components` Node.
4.  **Attach Standard Components**:
    -   `HealthComponent` (for life/death)
    -   `MovementController` (for physics/navigation)
    -   `AnimationController` (for state machine animations)
    -   `InteractionController` (for ability to interact with world)
    -   `NPCBrain` (if AI controlled)
5.  **Scripting**: Create a script extending `CharacterBody2D` (e.g., `MyNPC.gd`).
    -   Export references to components: `@onready var health_component = $Components/HealthComponent`

### 2. Creating a New Interactive Object (Tree/Rock)

1.  **Create Scene**: Inherit from `Node2D` or `StaticBody2D`.
2.  **Add Visuals**: Create a `Visuals` Node2D.
3.  **Add Collision**: `CollisionShape2D` (if blocking).
4.  **Attach Standard Components**:
    -   `InteractableComponent` (to receive interactions)
    -   `HealthComponent` (for durability)
    -   `AnimationController` (for hit/die effects)
5.  **Scripting**: Connect `HealthComponent.died` signal to `queue_free()` or death logic.

### 3. Adding Interaction

-   **Actor (Initiator)**: Add a child node to `InteractionController` (e.g., `ChopBehavior`).
-   **Object (Receiver)**: Add `InteractableComponent` to the object and set `interaction_label`.

## Common Tasks

-   **Check Compliance**: Verify if an entity follows the node structure in [entity_architecture.md](references/entity_architecture.md).
-   **Fix Components**: If an entity handles health logic in its main script, move it to `HealthComponent`.
