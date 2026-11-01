# LSC Stairs for SketchUp

An offline parametric stair extension extracted from [LSC Spatial Workbench](https://github.com/Lsc1123/sketchup-spatial-workbench). MIT licensed. Stable version **0.2.0**.

![Stair inspector and preview](docs/interface.png)

Supports straight, straight with an intermediate landing, L and U stairs, editable platforms, round handrails and posts. Create from dimensions or two picked endpoints. The Apple-inspired inspector offers live isometric, plan and side previews; one pure Ruby solver drives both preview and model geometry.

Six geometry styles: standard steps, solid flights, sloped waist slabs, open treads, twin stringers and a central spine. Styles set plate and beam dimensions, with real editable geometry; they never assign materials. Primary stair dimensions and railing settings are retained. Plate thickness and beam dimensions remain customizable. Older components default to the standard style.

Terminal floor plates and their perimeter railings are omitted. The stair meets the existing lower and upper floors directly; only intermediate landings are generated. Picked endpoints refer to the flight-to-floor connection edges.

Download [lsc-stairs-0.2.0.rbz](https://github.com/Lsc1123/sketchup-stair-generator/releases/download/v0.2.0/lsc-stairs-0.2.0.rbz), install with SketchUp Extension Manager, restart SketchUp, then open **Extensions → LSC 楼梯生成器**. The interface is currently in Chinese. Development target: SketchUp 2021+. Windows SketchUp 2025 native API and key HtmlDialog callbacks have been validated; native macOS acceptance remains pending. See [validation](docs/validation.md) for the scope and installation limitations.

Select an existing top-level LSC stair and read its parameters to update it. Rebuilds preserve the instance transform, name, tag and material and make the instance unique before changing its definition. Internal manual edits are replaced by parameter updates; SketchUp Undo can restore them.

Each flight uses n risers and n−1 treads. Picked endpoints are fixed coordinate snapshots. There is no automatic building cutting, clearance check or code compliance validation. Railings are schematic components, without infill or construction detailing.

Development checks:

```sh
ruby tests/core_test.rb
ruby tests/styles_test.rb
ruby tests/controller_test.rb
ruby tests/compatibility_test.rb
ruby tools/check_syntax.rb
node --check src/lsc_stairs/ui/app.js
python3 tests/package_test.py
python3 tools/package.py
```

The package has no runtime network access or third-party dependencies. See [provenance](docs/provenance.md) and [contribution guidelines](CONTRIBUTING.md).
