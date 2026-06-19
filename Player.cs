using Godot;

public partial class Player : CharacterBody3D
{
    [Export] public int Speed { get; set; } = 14;
    [Export] public int FallAcceleration { get; set; } = 75;
    [Export] public float JumpImpulse { get; set; } = 20.0f;
    [Export] public float Acceleration { get; set; } = 8.0f;
    [Export] public float RotationSpeed { get; set; } = 10.0f;
    [Export] public float SprintSpeedMultiplier { get; set; } = 1.3f;
    [Export] public float SprintAccelMultiplier { get; set; } = 2.0f;
    [Export] public float SquashChargeBonus { get; set; } = 0.3f;

    private const float SprintDrainRate = 0.5f;    // full charge lasts 2 seconds
    private const float SprintRechargeRate = 0.1f; // 10% per second
    private float _sprintCharge = 1.0f;

    private Vector3 _targetVelocity = Vector3.Zero;
    private bool _isDead = false;

    private const int TrajectorySteps = 25;
    private Node3D _highlightedMob = null;
    [Export] public bool DustEmitting { get; set; } = false;
    private GpuParticles3D _dustParticles;
    private Vector3 _prevPosition = Vector3.Zero;
    private ProgressBar _sprintBar;
    private AudioStreamPlayer _windPlayer;
    private AudioStreamGeneratorPlayback _windPlayback;
    private float _windFilter = 0f;
    private AudioStreamPlayer3D _jumpSfx;
    private AudioStreamPlayer3D _squishSfx;

    public override void _Ready()
    {
        // Layer scheme: player=1, mobs=2, ground=3.
        // Player mask = layer 3 only: stand on ground, pass through mobs.
        CollisionMask = 4;
        AddToGroup("players");

        var mobArea = new Area3D();
        mobArea.Name = "MobArea";
        mobArea.CollisionLayer = 0;
        mobArea.CollisionMask = 2;
        var areaShape = new CollisionShape3D();
        var sphere = new SphereShape3D { Radius = 0.83f };
        areaShape.Shape = sphere;
        areaShape.Position = new Vector3(0, 0.23f, 0);
        mobArea.AddChild(areaShape);
        AddChild(mobArea);

        var playerArea = new Area3D();
        playerArea.Name = "PlayerArea";
        playerArea.CollisionLayer = 0;
        playerArea.CollisionMask = 1; // detect other players
        var playerShape = new CollisionShape3D();
        playerShape.Shape = new SphereShape3D { Radius = 0.9f };
        playerShape.Position = new Vector3(0, 0.23f, 0);
        playerArea.AddChild(playerShape);
        AddChild(playerArea);

        _SetupDustParticles();
        _SetupSprintBar();
        if (IsMultiplayerAuthority())
            _SetupWindSound();

        _jumpSfx = new AudioStreamPlayer3D { Stream = ResourceLoader.Load<AudioStream>("res://audio/jump.mp3"), UnitSize = 10f };
        _squishSfx = new AudioStreamPlayer3D { Stream = ResourceLoader.Load<AudioStream>("res://audio/squish.mp3"), UnitSize = 10f };
        AddChild(_jumpSfx);
        AddChild(_squishSfx);

        if (!InputMap.HasAction("sprint"))
        {
            InputMap.AddAction("sprint");
            InputMap.ActionAddEvent("sprint", new InputEventKey { Keycode = Key.Shift });
            InputMap.ActionAddEvent("sprint", new InputEventJoypadButton { ButtonIndex = JoyButton.B });
        }

        var config = new SceneReplicationConfig();
        config.AddProperty(new NodePath(".:position"));
        config.AddProperty(new NodePath("Pivot:rotation"));
        config.AddProperty(new NodePath(".:DustEmitting"));
        var sync = new MultiplayerSynchronizer { Name = "Sync", ReplicationConfig = config };
        AddChild(sync);
        sync.SetMultiplayerAuthority(GetMultiplayerAuthority());
    }

    private void _SetupSprintBar()
    {
        if (!IsMultiplayerAuthority())
            return;

        var canvas = new CanvasLayer { Layer = 10 };
        AddChild(canvas);

        var container = new VBoxContainer();
        container.AnchorLeft   = 0.5f;
        container.AnchorRight  = 0.5f;
        container.AnchorTop    = 1.0f;
        container.AnchorBottom = 1.0f;
        container.OffsetLeft   = -80f;
        container.OffsetRight  =  80f;
        container.OffsetTop    = -56f;
        container.OffsetBottom = -16f;
        canvas.AddChild(container);

        var label = new Label
        {
            Text = "SPRINT",
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        label.AddThemeFontSizeOverride("font_size", 11);
        var font = ResourceLoader.Load<FontFile>("res://fonts/Montserrat-Medium.ttf");
        if (font != null)
            label.AddThemeFontOverride("font", font);
        container.AddChild(label);

        var fillStyle = new StyleBoxFlat { BgColor = new Color(1.0f, 0.78f, 0.1f) };
        fillStyle.SetCornerRadiusAll(3);
        var bgStyle = new StyleBoxFlat { BgColor = new Color(0.15f, 0.15f, 0.15f, 0.75f) };
        bgStyle.SetCornerRadiusAll(3);

        _sprintBar = new ProgressBar
        {
            MinValue = 0.0,
            MaxValue = 1.0,
            Value = 1.0,
            ShowPercentage = false,
            CustomMinimumSize = new Vector2(0, 14),
        };
        _sprintBar.AddThemeStyleboxOverride("fill", fillStyle);
        _sprintBar.AddThemeStyleboxOverride("background", bgStyle);
        container.AddChild(_sprintBar);
    }

    private void _SetupDustParticles()
    {
        var processMat = new ParticleProcessMaterial();
        processMat.Direction = new Vector3(0, 1, 0);
        processMat.Spread = 80.0f;
        processMat.InitialVelocityMin = 0.3f;
        processMat.InitialVelocityMax = 1.2f;
        processMat.Gravity = new Vector3(0, -3.0f, 0);
        processMat.SetParamMin(ParticleProcessMaterial.Parameter.Scale, 0.06f);
        processMat.SetParamMax(ParticleProcessMaterial.Parameter.Scale, 0.18f);

        var gradient = new Gradient();
        gradient.SetColor(0, new Color(0.76f, 0.64f, 0.44f, 0.55f));
        gradient.SetColor(1, new Color(0.76f, 0.64f, 0.44f, 0.0f));
        processMat.ColorRamp = new GradientTexture1D { Gradient = gradient };

        var quadMesh = new QuadMesh { Size = new Vector2(0.14f, 0.14f) };
        var meshMat = new StandardMaterial3D
        {
            BillboardMode = BaseMaterial3D.BillboardModeEnum.Enabled,
            VertexColorUseAsAlbedo = true,
            Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
            ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
        };
        quadMesh.Material = meshMat;

        _dustParticles = new GpuParticles3D
        {
            Amount = 20,
            Lifetime = 0.55,
            Randomness = 0.5f,
            TopLevel = true,
            Emitting = false,
            ProcessMaterial = processMat,
        };
        _dustParticles.DrawPasses = 1;
        _dustParticles.SetDrawPassMesh(0, quadMesh);

        AddChild(_dustParticles);
    }

    public override void _ExitTree()
    {
        // Clear mob highlight when this player node is freed (death or disconnect).
        if (_highlightedMob != null && IsInstanceValid(_highlightedMob))
            _highlightedMob.Call("set_highlighted", false);
    }

    public override void _PhysicsProcess(double delta)
    {
        _UpdateDust(delta);
        _UpdateWindSound();

        if (!IsMultiplayerAuthority())
            return;

        if (_isDead)
            return;

        if (Position.Y < -5.0f)
        {
            _isDead = true;
            _CallOnHost("_on_player_died", (int)Multiplayer.GetUniqueId());
            return;
        }

        var inputDirection = Vector3.Zero;
        if (Input.IsActionPressed("move_right"))  inputDirection.X += 1.0f;
        if (Input.IsActionPressed("move_left"))   inputDirection.X -= 1.0f;
        if (Input.IsActionPressed("move_forward")) inputDirection.Z -= 1.0f;
        if (Input.IsActionPressed("move_back"))   inputDirection.Z += 1.0f;

        if (inputDirection != Vector3.Zero)
        {
            inputDirection = inputDirection.Normalized();
            var pivot = GetNode<Node3D>("Pivot");
            var targetBasis = Basis.LookingAt(inputDirection);
            pivot.Basis = pivot.Basis.Slerp(targetBasis, RotationSpeed * (float)delta);
        }

        bool wantsSprint = Input.IsActionPressed("sprint") && inputDirection != Vector3.Zero;
        bool isSprinting = wantsSprint && _sprintCharge > 0.0f;

        if (isSprinting)
            _sprintCharge = Mathf.Max(0.0f, _sprintCharge - SprintDrainRate * (float)delta);
        else if (!wantsSprint)
            _sprintCharge = Mathf.Min(1.0f, _sprintCharge + SprintRechargeRate * (float)delta);

        if (_sprintBar != null)
            _sprintBar.Value = _sprintCharge;

        float effectiveSpeed = isSprinting ? Speed * SprintSpeedMultiplier : Speed;
        float effectiveAccel = isSprinting ? Acceleration * SprintAccelMultiplier : Acceleration;

        _targetVelocity.X = Mathf.Lerp(_targetVelocity.X, inputDirection.X * effectiveSpeed, effectiveAccel * (float)delta);
        _targetVelocity.Z = Mathf.Lerp(_targetVelocity.Z, inputDirection.Z * effectiveSpeed, effectiveAccel * (float)delta);

        if (IsOnFloor())
        {
            if (Input.IsActionJustPressed("jump"))
            {
                _targetVelocity.Y = JumpImpulse;
                Rpc(nameof(_PlayJumpSfx));
            }
            else
                _targetVelocity.Y = 0.0f;
        }
        else
        {
            _targetVelocity.Y -= FallAcceleration * (float)delta;
        }

        Velocity = _targetVelocity;
        MoveAndSlide();
        _CheckSquash();
        _CheckMobContact();
        _CheckPlayerBounce();
        _UpdateTrajectory();
    }

    public void TriggerDeathExplosion()
    {
        if (!IsInsideTree()) return;
        var processMat = new ParticleProcessMaterial();
        processMat.Direction = Vector3.Up;
        processMat.Spread = 180.0f;
        processMat.InitialVelocityMin = 3.0f;
        processMat.InitialVelocityMax = 10.0f;
        processMat.Gravity = new Vector3(0, -6.0f, 0);
        processMat.SetParamMin(ParticleProcessMaterial.Parameter.Scale, 0.12f);
        processMat.SetParamMax(ParticleProcessMaterial.Parameter.Scale, 0.45f);

        var scaleCurve = new Curve();
        scaleCurve.AddPoint(new Vector2(0.0f, 1.0f));
        scaleCurve.AddPoint(new Vector2(0.6f, 0.6f));
        scaleCurve.AddPoint(new Vector2(1.0f, 0.0f));
        processMat.SetParamTexture(ParticleProcessMaterial.Parameter.Scale, new CurveTexture { Curve = scaleCurve });

        var gradient = new Gradient();
        gradient.SetColor(0, new Color(1.0f, 0.88f, 0.15f, 1.0f));
        gradient.SetColor(1, new Color(1.0f, 0.15f, 0.0f, 0.0f));
        processMat.ColorRamp = new GradientTexture1D { Gradient = gradient };

        var mesh = new SphereMesh { Radius = 0.15f, Height = 0.3f, RadialSegments = 4, Rings = 2 };
        mesh.Material = new StandardMaterial3D
        {
            ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
            VertexColorUseAsAlbedo = true,
            Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
        };

        var burst = new GpuParticles3D
        {
            Amount = 52,
            Lifetime = 1.4,
            OneShot = true,
            Explosiveness = 0.95f,
            ProcessMaterial = processMat,
            GlobalPosition = GlobalPosition + Vector3.Up * 0.5f,
        };
        burst.DrawPasses = 1;
        burst.SetDrawPassMesh(0, mesh);

        GetTree().Root.AddChild(burst);
        burst.Emitting = true;

        var cleanup = new Timer { WaitTime = 2.5, OneShot = true };
        cleanup.Timeout += () => { burst.QueueFree(); cleanup.QueueFree(); };
        GetTree().Root.AddChild(cleanup);
        cleanup.Start();
    }

    private void _UpdateDust(double delta)
    {
        if (IsMultiplayerAuthority())
        {
            var horizontalDelta = new Vector2(GlobalPosition.X - _prevPosition.X, GlobalPosition.Z - _prevPosition.Z);
            DustEmitting = IsOnFloor() && horizontalDelta.Length() > 0.001f;
            _prevPosition = GlobalPosition;
        }

        _dustParticles.Emitting = DustEmitting;
        _dustParticles.GlobalPosition = GlobalPosition + new Vector3(0, -0.3f, 0);
    }

    private void _SetupWindSound()
    {
        var gen = new AudioStreamGenerator { MixRate = 22050, BufferLength = 0.1f };
        _windPlayer = new AudioStreamPlayer { Stream = gen };
        AddChild(_windPlayer);
        _windPlayer.Play();
        _windPlayback = (AudioStreamGeneratorPlayback)_windPlayer.GetStreamPlayback();
    }

    private void _UpdateWindSound()
    {
        if (_windPlayback == null)
            return;

        float hSpeed = IsOnFloor() ? new Vector2(Velocity.X, Velocity.Z).Length() : 0f;
        float t = Mathf.Clamp(hSpeed / (Speed * SprintSpeedMultiplier), 0f, 1f);
        float t2 = t * t; // quadratic — effect stays subtle until you're really moving

        float amplitude = t2 * 0.11f;
        // Low speed: cutoff ~100 Hz (muffled rumble). High speed: cutoff ~5 kHz (bright hiss).
        float filterCoef = Mathf.Lerp(0.97f, 0.25f, t2);

        int frames = _windPlayback.GetFramesAvailable();
        for (int i = 0; i < frames; i++)
        {
            float noise = ((float)GD.Randf() * 2f - 1f) * amplitude;
            _windFilter = _windFilter * filterCoef + noise * (1f - filterCoef);
            _windPlayback.PushFrame(new Vector2(_windFilter, _windFilter));
        }
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
    private void _PlayJumpSfx() => _jumpSfx.Play();

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
    private void _PlaySquishSfx() => _squishSfx.Play();

    private void _CallOnHost(StringName method, params Variant[] args)
    {
        var main = GetNode<Node>("/root/Main");
        if (Multiplayer.IsServer())
            main.Call(method, args);
        else
            main.RpcId(1, method, args);
    }

    private void _CheckSquash()
    {
        if (_targetVelocity.Y >= 0.0f)
            return;

        foreach (var node in GetTree().GetNodesInGroup("mobs"))
        {
            if (node is not Node3D mob || !IsInstanceValid(mob))
                continue;

            var diff = GlobalPosition - mob.GlobalPosition;
            var horizontalDist = new Vector2(diff.X, diff.Z).Length();

            if (diff.Y > 0.7f && diff.Y < 1.8f && horizontalDist < 1.5f)
            {
                _targetVelocity.Y = JumpImpulse;
                _sprintCharge = Mathf.Min(1.0f, _sprintCharge + SquashChargeBonus);
                Rpc(nameof(_PlaySquishSfx));
                _CallOnHost("_on_squash_request", ((Node)mob).Name, (int)Multiplayer.GetUniqueId());
                return;
            }
        }
    }

    private void _CheckMobContact()
    {
        if (_targetVelocity.Y > 0.0f)
            return;

        var mobArea = GetNode<Area3D>("MobArea");
        foreach (var body in mobArea.GetOverlappingBodies())
        {
            if (!body.IsInGroup("mobs"))
                continue;

            var diffY = GlobalPosition.Y - ((Node3D)body).GlobalPosition.Y;
            if (diffY > 0.7f)
                continue;

            _isDead = true;
            _CallOnHost("_on_player_died", (int)Multiplayer.GetUniqueId());
            return;
        }
    }

    private void _CheckPlayerBounce()
    {
        var playerArea = GetNode<Area3D>("PlayerArea");
        foreach (var body in playerArea.GetOverlappingBodies())
        {
            if (body == this || body is not CharacterBody3D other)
                continue;
            if (!other.IsInGroup("players"))
                continue;

            var push = GlobalPosition - other.GlobalPosition;
            push.Y = 0f;
            if (push.LengthSquared() < 0.0001f)
                push = Vector3.Right;
            else
                push = push.Normalized();

            float combinedSpeed = Mathf.Max(4f, new Vector2(_targetVelocity.X, _targetVelocity.Z).Length());
            _targetVelocity.X = push.X * combinedSpeed;
            _targetVelocity.Z = push.Z * combinedSpeed;
        }
    }

    private void _UpdateTrajectory()
    {
        if (_highlightedMob != null && !IsInstanceValid(_highlightedMob))
            _highlightedMob = null;

        if (IsOnFloor())
        {
            if (_highlightedMob != null)
            {
                _highlightedMob.Call("set_highlighted", false);
                _highlightedMob = null;
            }
            return;
        }

        var pos = GlobalPosition;
        var vel = _targetVelocity;
        Node3D squashTarget = null;

        for (int i = 0; i < TrajectorySteps; i++)
        {
            const float dt = 0.05f;
            vel.Y -= FallAcceleration * dt;
            pos += vel * dt;
            if (pos.Y < 0.0f) break;

            foreach (var node in GetTree().GetNodesInGroup("mobs"))
            {
                if (node is not Node3D mob || !IsInstanceValid(mob)) continue;
                var diff = pos - mob.GlobalPosition;
                var hDist = new Vector2(diff.X, diff.Z).Length();
                if (diff.Y > 0.7f && diff.Y < 1.8f && hDist < 1.5f)
                {
                    squashTarget = mob;
                    break;
                }
            }
            if (squashTarget != null) break;
        }

        if (squashTarget != _highlightedMob)
        {
            if (_highlightedMob != null && IsInstanceValid(_highlightedMob))
                _highlightedMob.Call("set_highlighted", false);
            _highlightedMob = squashTarget;
            if (_highlightedMob != null)
                _highlightedMob.Call("set_highlighted", true);
        }
    }
}
