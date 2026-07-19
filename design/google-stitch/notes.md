# Design System Strategy: The Sonic Architecture

## 1. Overview & Creative North Star
The Creative North Star for this system is **"The Technical Monolith."** 

Unlike consumer-grade audio apps that rely on playful roundness and bright gradients, this system is inspired by high-end rack-mounted studio hardware and brutalist architectural precision. It treats the interface not as a webpage, but as a precision instrument. We break the "template" look by utilizing a high-contrast typographic scale—pairing massive, editorial display headers with hyper-dense, technical metadata. The layout favors intentional asymmetry, where large blocks of negative space create a "breathing" canvas for dense clusters of controls.

## 2. Color Theory & Tonal Depth
This system rejects the "flat" dark mode. We use a spectrum of charcoals and slates to create a sense of physical space.

### The "No-Line" Rule
**Borders are a failure of hierarchy.** Designers are strictly prohibited from using 1px solid lines to separate major sections. Boundaries must be defined through background shifts. For example:
- A sidebar uses `surface_container_low`.
- The main content area uses `surface`.
- Nested panels use `surface_container_high`.
The eye should perceive a change in "material" rather than a line on a page.

### Surface Hierarchy & Nesting
Treat the UI as a series of stacked slabs. 
- **Base Level:** `surface` (#131313) for the background.
- **Level 1 (Sub-sections):** `surface_container_low` (#1C1B1B).
- **Level 2 (Active Modules):** `surface_container_high` (#2A2A2A).
- **Level 3 (Interactive Floating):** `surface_bright` (#393939).

### The "Glass & Gradient" Rule
To elevate the "Pro-Audio" feel, floating controllers or transport bars must use Glassmorphism. Apply `surface_container` at 80% opacity with a `20px` backdrop blur. For primary actions, use a subtle linear gradient from `primary` (#D0BCFF) to `primary_container` (#A078FF) at a 135-degree angle to simulate the glow of an internal LED.

## 3. Typography: Editorial vs. Technical
The system utilizes a dual-font approach to balance "High-End Editorial" with "Precision Engineering."

*   **Display & Headlines (Manrope):** Used for large-scale branding and section headers (`display-lg` to `headline-sm`). This typeface provides a modern, geometric authority.
*   **Technical Metadata (Inter):** Used for everything else (`title-sm` to `label-sm`). Inter's high x-height ensures that track titles, BPMs, and bitrates remain legible even at the smallest scales.
*   **Hierarchy Note:** Use `on_surface_variant` (#CBC3D7) for secondary labels to create a sophisticated "receded" effect, reserving `on_surface` (#E5E2E1) for active, high-priority data.

## 4. Elevation & Depth
We define depth through light physics, not drop-shadow presets.

*   **The Layering Principle:** Instead of a shadow, place a `surface_container_lowest` (#0E0E0E) element behind a `surface_container_low` element to create a "recessed" well effect—common in physical audio mixers.
*   **Ambient Shadows:** If an element must float (like a context menu), use a shadow with a 40px blur at 6% opacity, using a tint of `primary_fixed_variant` (#5516BE) instead of pure black.
*   **The "Ghost Border" Fallback:** If accessibility requires a stroke (e.g., in high-density grids), use `outline_variant` (#494454) at **20% opacity**. It should be felt, not seen.

## 5. Component Logic

### Genre Toggle Buttons (The "Grid 30")
Standard buttons look cluttered in groups of 30. Use a "Micro-Slab" approach:
- **Default:** `surface_container_high` with `label-md` text. No border.
- **Active State:** Background shifts to `secondary_container` (#03C6B2). Text shifts to `on_secondary_container` (#004D44). 
- **Interaction:** On hover, apply a `primary` (#D0BCFF) top-edge "glow" (a 2px top-only border) to mimic a physical light turning on.

### Input Fields & Sliders
- **Inputs:** Use `surface_container_lowest`. No borders. Use a `1.5` (0.3rem) corner radius for a "machined" look.
- **Sliders (Faders):** The track should be `surface_container_highest`. The "thumb" or handle should be `secondary` (#44E2CD), glowing with a subtle outer glow of the same color.

### Cards & Lists
**Forbid divider lines.** Use the Spacing Scale `4` (0.9rem) or `5` (1.1rem) to create clear groupings. If a list is extremely dense, use alternating row tints between `surface` and `surface_container_low`.

### Specialized Audio Components
- **Waveform Display:** Use `secondary` for the rendered waveform and `primary_container` for the "played" portion. 
- **Level Meters:** Use a gradient ramp from `secondary` to `tertiary` (#FFB869) for peak signals, avoiding standard "Green-Yellow-Red" for a more bespoke "Teal-Violet-Amber" pro palette.

## 6. Do's and Don'ts

### Do
*   **Do** use `2.5` (0.5rem) spacing as your default gutter for a tight, technical feel.
*   **Do** use `9999px` (full) rounding only for pills/tags. All structural elements should stay between `sm` (0.125rem) and `md` (0.375rem).
*   **Do** use `on_tertiary_fixed_variant` for "Warning" or "Experimental" features to provide a warm, premium alert state.

### Don't
*   **Don't** use pure white (#FFFFFF). It breaks the dark-room studio aesthetic. Always use `on_surface`.
*   **Don't** use standard "drop shadows." Use tonal layering (shifting between `surface_container` tiers).
*   **Don't** center-align technical data. Precision instruments are always left or right-aligned for rapid scanning.