# Squash the Creeps (3D)

A multiplayer 3D action game built with Godot 4, inspired by the official Godot "Squash the Creeps" tutorial but expanded with multiplayer support and enhanced gameplay features.

## Game Overview

Players control characters on a 3D arena, jumping on enemy mobs (called "creeps") to squash them and score points. The last player standing wins! Mobs spawn continuously and increase in speed and aggression over time.

## Features

### Multiplayer
- **Host/Join System**: Create a server or connect to an existing game via IP address and port
- **Lobby System**: Players gather in a lobby before the game starts
- **Up to 4 Players**: Support for multiplayer matches with up to 4 players
- **Peer-to-Peer Networking**: Uses ENet for reliable multiplayer connectivity
- **Synchronized Gameplay**: All player movements and mob states are synchronized across clients

### Player Abilities
- **Movement**: WASD or controller stick to move in any direction
- **Jumping**: Jump to reach higher platforms or stomp on mobs
- **Sprinting**: Hold Shift or B button to sprint with increased speed (drains stamina)
- **Stamina System**: Sprint meter that drains when sprinting and recharges when walking
- **Bounce on Other Players**: Collide with other players to bounce off them
- **Dust Particles**: Visual dust effect when moving on the ground
- **Wind Sound**: Procedurally generated wind sound based on movement speed

### Mob Behavior
- **Targeted Spawning**: Mobs spawn and target a random player
- **Increasing Difficulty**: Mob speed increases over time (up to 120 seconds)
- **Soft Repulsion**: Mobs gently push each other to avoid pile-ups
- **Visual Highlight**: Yellow torus highlights the mob you're about to land on

### Squash Mechanic
- Land on a mob from above to squash it and earn a point
- Trajectory Prediction: See where you'll land with trajectory preview
- Landing on a mob also gives a small stamina boost
- Missing a squash (falling past the mob) leaves you vulnerable

### Scoring & UI
- **Live Leaderboard**: Top-right corner shows current scores
- **Player Labels**: Each player is labeled P1, P2, P3, P4
- **Game Over Screen**: Final rankings with restart/quit options
- **Music Fade**: Background music fades in/out during gameplay

### Controls
| Action | Keyboard | Controller |
|--------|----------|------------|
| Move | WASD | Left Stick |
| Jump | Space | A / Cross |
| Sprint | Shift | B / Circle |
| Menu | Escape | Start / Options |
| Lobby Confirm | Enter / Space | A / Cross |

## Technical Details

- **Engine**: Godot 4.x
- **Language**: C# (Player.cs) and GDScript (main.gd, mob.gd)
- **Networking**: ENetMultiplayerPeer
- **Multiplayer Authority**: Server authoritative with client-side prediction

## Project Structure

```
├── main.gd           # Main game logic, networking, UI management
├── mob.gd            # Mob enemy behavior and physics
├── Player.cs         # Player character with all abilities
├── main.tscn         # Main scene
├── player.tscn       # Player scene
├── mob.tscn          # Mob scene
├── project.godot     # Godot project configuration
├── art/              # 3D models and textures
├── audio/            # Sound effects and music
└── fonts/            # UI fonts (SIL Open Font License)
```

## Licensing Note

This game was created following the official Godot "Squash the Creeps" tutorial. I did not create the assets or the idea behind it.