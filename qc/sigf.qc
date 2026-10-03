// Counter-Strike 1.6 Takeover: Terrorists and Counter-Terrorists invade Quake, with CS weapons,
// headshots, kill feed, cash drops, flashbangs and a ticking bomb.

.float sigf_goal_yaw;
.float sigf_team;          // 1 = Terrorist, 2 = Counter-Terrorist
.float sigf_hs;            // the last hit on this victim was a headshot
.float sigf_money;         // player cash
.float sigf_value;         // cash on a pickup
.float sigf_scan_t;
.float sigf_spray;
.float sigf_spray_end;
.float sigf_flash_until;
.float sigf_flash_cmd;
.float sigf_fuse_end;
.float sigf_fuse_total;
.float sigf_phase;
.float sigf_pkills;
.float sigf_init;
.float sigf_msg_t;
.float sigf_moved;
.float sigf_keep_t;
.float sigf_spawn_t;
.float sigf_next_bomb;
.float sigf_blind_until;

float sigf_alt;
float sigf_round;
float sigf_bomb_hp = 500;
float sigf_bomb_fuse = 16;

void() sigf_bomb_spawn;
void() sigf_bomb_idle = { };

// ---------- text helpers ----------
string(entity e) sigf_name =
{
    if (e.classname == "player") return "You";
    if (e.classname == "sigf_t") return "Terrorist";
    if (e.classname == "sigf_ct") return "Counter-Terrorist";
    if (e.classname == "sigf_bomb") return "C4";
    if (e.classname == "monster_ogre") return "Ogre";
    if (e.classname == "monster_demon1") return "Fiend";
    if (e.classname == "monster_knight") return "Knight";
    if (e.classname == "monster_dog") return "Rottweiler";
    if (e.classname == "monster_zombie") return "Zombie";
    if (e.classname == "monster_shambler") return "Shambler";
    if (e.classname == "monster_wizard") return "Scrag";
    if (e.classname == "monster_hell_knight") return "Death Knight";
    if (e.classname == "monster_shalrath") return "Vore";
    if (e.classname == "monster_tarbaby") return "Spawn";
    return "Monster";
};

string(entity e) sigf_wname =
{
    if (e.classname == "sigf_t") return "AK-47";
    if (e.classname == "sigf_ct") return "M4A1";
    if (e.classname != "player") return "Claws";
    if (e.weapon == IT_SHOTGUN) return "Desert Eagle";
    if (e.weapon == IT_SUPER_SHOTGUN) return "AWP";
    if (e.weapon == IT_NAILGUN) return "AK-47";
    if (e.weapon == IT_SUPER_NAILGUN) return "M249";
    if (e.weapon == IT_GRENADE_LAUNCHER) return "HE Grenade";
    if (e.weapon == IT_ROCKET_LAUNCHER) return "Flashbang";
    return "Knife";
};

void(float amount) sigf_cash_text =
{
    sprint(self, "$");
    sprint(self, ftos(amount));
    sprint(self, "\n");
};

// ---------- tracer, blood and impacts ----------
void(vector a, vector b, float col) sigf_tracer =
{
    local vector step, p;
    local float len, n;
    len = vlen(b - a);
    if (len < 40) return;
    step = normalize(b - a) * 28;
    p = a + step * 2;
    n = 0;
    while (n < 60 && vlen(b - p) > 28)
    {
        particle(p, '0 0 0', col, 3);
        p = p + step;
        n = n + 1;
    }
};

void(vector org) sigf_puff =
{
    WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
    WriteByte(MSG_BROADCAST, TE_GUNSHOT);
    WriteCoord(MSG_BROADCAST, org_x);
    WriteCoord(MSG_BROADCAST, org_y);
    WriteCoord(MSG_BROADCAST, org_z);
};

// One bullet (or a piercing sniper round) from the player's eye. Headshots triple the damage.
void(float dmg, float spread, float maxhits) sigf_shoot =
{
    local vector src, dir, from, end, org;
    local entity victim, ignore;
    local float hits, head, d, loops, go;

    makevectors(self.v_angle);
    dir = normalize(v_forward + crandom() * spread * v_right + crandom() * spread * v_up);
    src = self.origin + self.view_ofs;
    from = src;
    ignore = self;
    hits = 0;
    loops = 0;
    go = TRUE;
    self.effects = self.effects | EF_MUZZLEFLASH;
    while (go && loops < 4)
    {
        loops = loops + 1;
        traceline(from, from + dir * 4096, FALSE, ignore);
        end = trace_endpos;
        victim = trace_ent;
        if (loops == 1)
            sigf_tracer(src + v_forward * 20 + v_right * 8 - v_up * 8, end, 192);
        else
            sigf_tracer(from, end, 192);
        org = end - dir * 4;
        if (victim.takedamage)
        {
            head = FALSE;
            if ((victim.flags & FL_MONSTER) && end_z > victim.absmax_z - victim.size_z * 0.25)
                head = TRUE;
            d = dmg;
            victim.sigf_hs = 0;
            if (head)
            {
                d = dmg * 3;
                if (victim.classname == "sigf_ct")
                    d = dmg * 1.8;           // the helmet soaks some of it
                victim.sigf_hs = 1;
                particle(org, '0 0 70', 73, 30);
                sound(victim, CHAN_ITEM, "sigf/dink.wav", 1, ATTN_NORM);
            }
            SpawnBlood(org, dir * 60, d);
            T_Damage(victim, self, self, d);
            hits = hits + 1;
            ignore = victim;
            from = end + dir * 4;
            if (hits >= maxhits)
                go = FALSE;
        }
        else
        {
            sigf_puff(org);
            if (random() < 0.4)
                sound(self, CHAN_AUTO, "sigf/rico.wav", 0.6, ATTN_STATIC);
            go = FALSE;
        }
    }
};

// ---------- the player's weapons (called from weapons.qc) ----------
void() sigf_fire_ak =
{
    if (self.ammo_nails < 1)
    {
        self.weapon = W_BestWeapon();
        W_SetCurrentAmmo();
        return;
    }
    sound(self, CHAN_WEAPON, "sigf/ak.wav", 1, ATTN_NORM);
    self.attack_finished = time + 0.1;
    self.currentammo = self.ammo_nails = self.ammo_nails - 1;
    if (time > self.sigf_spray_end)
        self.sigf_spray = 0;
    if (self.sigf_spray < 14)
        self.sigf_spray = self.sigf_spray + 1;
    self.sigf_spray_end = time + 0.3;
    sigf_shoot(9, 0.008 + self.sigf_spray * 0.004, 1);   // the spray widens while the trigger is held
    self.punchangle_x = -2;
};

void() sigf_fire_m249 =
{
    if (self.ammo_nails < 2)
    {
        self.weapon = W_BestWeapon();
        W_SetCurrentAmmo();
        return;
    }
    sound(self, CHAN_WEAPON, "sigf/ak.wav", 1, ATTN_NORM);
    self.attack_finished = time + 0.1;
    self.currentammo = self.ammo_nails = self.ammo_nails - 2;
    sigf_shoot(7, 0.03, 1);
    sigf_shoot(7, 0.03, 1);
    self.punchangle_x = -3;
};

void() sigf_fire_deagle =
{
    sound(self, CHAN_WEAPON, "sigf/deagle.wav", 1, ATTN_NORM);
    self.currentammo = self.ammo_shells = self.ammo_shells - 1;
    self.punchangle_x = -6;
    sigf_shoot(40, 0.004, 1);
};

void() sigf_fire_awp =
{
    sound(self, CHAN_WEAPON, "sigf/awp.wav", 1, ATTN_NORM);
    self.currentammo = self.ammo_shells = self.ammo_shells - 1;
    self.punchangle_x = -10;
    sigf_shoot(160, 0, 3);                      // pierces up to three enemies in a row
    WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
    WriteByte(MSG_BROADCAST, TE_SPIKE);
    WriteCoord(MSG_BROADCAST, self.origin_x);
    WriteCoord(MSG_BROADCAST, self.origin_y);
    WriteCoord(MSG_BROADCAST, self.origin_z + 8);
};

// ---------- grenades: HE and flashbang, thrown by the player and by the soldiers ----------
void() sigf_flash_pop =
{
    local entity m;
    local vector eye, dirn;
    local float a, nblind;

    nblind = 0;
    sound(self, CHAN_WEAPON, "sigf/flash.wav", 1, ATTN_NONE);
    WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
    WriteByte(MSG_BROADCAST, TE_TELEPORT);
    WriteCoord(MSG_BROADCAST, self.origin_x);
    WriteCoord(MSG_BROADCAST, self.origin_y);
    WriteCoord(MSG_BROADCAST, self.origin_z);
    particle(self.origin, '0 0 0', 15, 120);
    self.effects = EF_BRIGHTLIGHT;
    m = findradius(self.origin, 700);
    while (m)
    {
        if (m.health > 0)
        {
            traceline(self.origin, m.origin + m.view_ofs, TRUE, self);
            if (trace_fraction == 1)
            {
                if (m.classname == "player")
                {
                    if (self.owner != m)
                    {
                        eye = m.origin + m.view_ofs;
                        dirn = normalize(self.origin - eye);
                        makevectors(m.v_angle);
                        if (v_forward * dirn > 0.35)
                        {
                            m.sigf_flash_until = time + 0.7;
                            sound(m, CHAN_VOICE, "sigf/flash.wav", 0.5, ATTN_NONE);
                        }
                    }
                }
                else if (m.flags & FL_MONSTER)
                {
                    m.attack_finished = time + 4;        // blinded: it cannot shoot
                    m.sigf_blind_until = time + 4;
                    particle(m.origin + '0 0 30', '0 0 40', 15, 25);
                    nblind = nblind + 1;
                }
            }
        }
        m = m.chain;
    }
    if (nblind > 0 && self.owner.classname == "player")
        sprint(self.owner, "Enemy blinded!\n");
    self.think = SUB_Remove;
    self.nextthink = time + 0.35;
    self.velocity = '0 0 0';
    self.movetype = MOVETYPE_NONE;
};

void() sigf_flash_touch =
{
    if (other == self.owner)
        return;
    sound(self, CHAN_WEAPON, "weapons/bounce.wav", 1, ATTN_NORM);
};

// kind 0 = HE grenade, 1 = flashbang
entity(entity own, vector org, vector vel, float kind) sigf_throw =
{
    local entity g;
    g = spawn();
    g.owner = own;
    g.movetype = MOVETYPE_BOUNCE;
    g.solid = SOLID_BBOX;
    g.classname = "grenade";
    g.velocity = vel;
    g.avelocity = '300 300 300';
    g.angles = vectoangles(vel);
    if (kind == 0)
        setmodel(g, "progs/sigf_nade.mdl");
    else
        setmodel(g, "progs/sigf_flashnade.mdl");
    setsize(g, '0 0 0', '0 0 0');
    setorigin(g, org);
    if (kind == 0)
    {
        g.touch = GrenadeTouch;
        g.think = GrenadeExplode;
        g.nextthink = time + 2.4;
    }
    else
    {
        g.touch = sigf_flash_touch;
        g.think = sigf_flash_pop;
        g.nextthink = time + 1.4;
    }
    return g;
};

void() sigf_fire_he =
{
    local vector vel;
    self.currentammo = self.ammo_rockets = self.ammo_rockets - 1;
    sound(self, CHAN_VOICE, "sigf/v_fire.wav", 1, ATTN_NORM);
    bprint("[RADIO] Fire in the hole!\n");
    self.punchangle_x = -2;
    makevectors(self.v_angle);
    vel = v_forward * 650 + v_up * 220;
    sigf_throw(self, self.origin + '0 0 16', vel, 0);
};

void() sigf_fire_flash =
{
    local vector vel;
    self.currentammo = self.ammo_rockets = self.ammo_rockets - 1;
    sound(self, CHAN_WEAPON, "weapons/grenade.wav", 1, ATTN_NORM);
    self.punchangle_x = -2;
    makevectors(self.v_angle);
    vel = v_forward * 700 + v_up * 200;
    sigf_throw(self, self.origin + '0 0 16', vel, 1);
};

// ---------- cash drops ----------
void() sigf_cash_touch =
{
    if (other.classname != "player")
        return;
    other.sigf_money = other.sigf_money + self.sigf_value;
    sound(other, CHAN_ITEM, "sigf/cash.wav", 1, ATTN_NORM);
    sprint(other, "+$");
    sprint(other, ftos(self.sigf_value));
    sprint(other, "   Money: $");
    sprint(other, ftos(other.sigf_money));
    sprint(other, "\n");
    stuffcmd(other, "bf\n");
    remove(self);
};

void(vector org, float value) sigf_drop_cash =
{
    local entity o;
    o = spawn();
    o.classname = "sigf_cash";
    o.movetype = MOVETYPE_TOSS;
    o.solid = SOLID_TRIGGER;
    o.sigf_value = value;
    setmodel(o, "progs/sigf_cash.mdl");
    setsize(o, '-18 -18 -24', '18 18 0');
    setorigin(o, org + '0 0 28');
    o.velocity_x = crandom() * 90;
    o.velocity_y = crandom() * 90;
    o.velocity_z = 280;
    o.avelocity = '0 180 0';
    o.effects = EF_DIMLIGHT;
    o.touch = sigf_cash_touch;
    o.nextthink = time + 40;
    o.think = SUB_Remove;
};

// ---------- the soldiers: Terrorist (team 1) and Counter-Terrorist (team 2) ----------
// Frames: 0-1 stand, 2-5 walk, 6-9 attack, 10-11 pain, 12-16 death.
void() cs_scan;
void() cs_run1;

void() cs_stand1 = [0, cs_stand2] { ai_stand(); cs_scan(); };
void() cs_stand2 = [1, cs_stand1] { ai_stand(); };

void() cs_walk1 = [2, cs_walk2] { ai_walk(5); cs_scan(); };
void() cs_walk2 = [3, cs_walk3] { ai_walk(5); };
void() cs_walk3 = [4, cs_walk4] { ai_walk(5); };
void() cs_walk4 = [5, cs_walk1] { ai_walk(5); };

void() cs_run2;
void() cs_run3;
void() cs_run4;
// soldiers stop and shoot at rifle range instead of walking into your face
float() cs_speed =
{
    if (self.enemy && enemy_vis && vlen(self.enemy.origin - self.origin) < 230)
        return 0;
    return 14;
};
void() cs_run1 = [2, cs_run2] { ai_run(cs_speed()); cs_scan(); };
void() cs_run2 = [3, cs_run3] { ai_run(cs_speed()); };
void() cs_run3 = [4, cs_run4] { ai_run(cs_speed()); };
void() cs_run4 = [5, cs_run1] { ai_run(cs_speed()); };

// one rifle bullet at the enemy; friendly fire between teammates is ignored
void() cs_shot =
{
    local vector src, dir;
    local float dmg;

    makevectors(self.angles);
    src = self.origin + v_forward * 18 + '0 0 6';
    dir = normalize(self.enemy.origin + '0 0 8' - src);
    dir = normalize(dir + crandom() * 0.05 * v_right + crandom() * 0.04 * v_up);
    traceline(src, src + dir * 2048, FALSE, self);
    sigf_tracer(src, trace_endpos, 194);
    self.effects = self.effects | EF_MUZZLEFLASH;
    sound(self, CHAN_WEAPON, "sigf/ak.wav", 1, ATTN_NORM);
    if (trace_ent.takedamage && trace_ent.classname != self.classname && trace_ent.classname != "sigf_bomb")
    {
        dmg = 4 + random() * 3;
        SpawnBlood(trace_endpos - dir * 4, dir * 40, dmg);
        T_Damage(trace_ent, self, self, dmg);
    }
    else if (!trace_ent.takedamage)
        sigf_puff(trace_endpos - dir * 4);
};

void() cs_atk1 = [6, cs_atk2] { ai_face(); };
void() cs_atk2 = [7, cs_atk3] { ai_face(); cs_shot(); };
void() cs_atk3 = [8, cs_atk4] { ai_face(); cs_shot(); };
void() cs_atk4 = [9, cs_atk5] { ai_face(); cs_shot(); };
void() cs_atk5 = [8, cs_atk6] { ai_face(); cs_shot(); SUB_CheckRefire(cs_atk1); };
void() cs_atk6 = [9, cs_run1] { ai_face(); };

void() cs_toss =
{
    local vector d, flat, vel;
    local float dist, spd;
    local entity g;

    d = self.enemy.origin - self.origin;
    flat = d;
    flat_z = 0;
    dist = vlen(flat);
    spd = dist * 1.5;
    if (spd > 900) spd = 900;
    vel = normalize(flat) * spd + '0 0 260';
    if (self.sigf_team == 2)
    {
        g = sigf_throw(self, self.origin + '0 0 16', vel, 1);
        sound(self, CHAN_VOICE, "sigf/v_go.wav", 1, ATTN_NORM);
        bprint("[RADIO] Counter-Terrorist: Flashbang out!\n");
    }
    else
    {
        g = sigf_throw(self, self.origin + '0 0 16', vel, 0);
        sound(self, CHAN_VOICE, "sigf/v_fire.wav", 1, ATTN_NORM);
        bprint("[RADIO] Terrorist: Fire in the hole!\n");
    }
};

void() cs_throw1 = [6, cs_throw2] { ai_face(); };
void() cs_throw2 = [7, cs_throw3] { ai_face(); };
void() cs_throw3 = [8, cs_throw4] { ai_face(); cs_toss(); };
void() cs_throw4 = [9, cs_run1] { ai_face(); };

void() cs_attack =
{
    local float dist;
    dist = vlen(self.enemy.origin - self.origin);
    if (dist > 320 && dist < 900 && random() < 0.3)
        cs_throw1();
    else
        cs_atk1();
};

void() cs_pain1 = [10, cs_pain2] { };
void() cs_pain2 = [11, cs_run1] { };

void(entity attacker, float damage) cs_pain =
{
    if (self.pain_finished > time)
        return;
    self.pain_finished = time + 0.8;
    if (random() < 0.5)
        sound(self, CHAN_VOICE, "soldier/pain1.wav", 1, ATTN_NORM);
    else
        sound(self, CHAN_VOICE, "soldier/pain2.wav", 1, ATTN_NORM);
    cs_pain1();
};

void() cs_die1 = [12, cs_die2] { };
void() cs_die2 = [13, cs_die3] { self.solid = SOLID_NOT; };
void() cs_die3 = [14, cs_die4] { };
void() cs_die4 = [15, cs_die5] { };
void() cs_die5 = [16, cs_die5] { };

void() cs_die =
{
    if (self.health < -35)
    {
        sound(self, CHAN_VOICE, "player/udeath.wav", 1, ATTN_NORM);
        ThrowGib("progs/gib1.mdl", self.health);
        ThrowGib("progs/gib2.mdl", self.health);
        ThrowHead("progs/h_player.mdl", self.health);
        return;
    }
    if (self.sigf_hs)
    {
        ThrowGib("progs/gib3.mdl", -60);         // the head pops off
        particle(self.origin + '0 0 24', '0 0 90', 73, 50);
    }
    sound(self, CHAN_VOICE, "soldier/death1.wav", 1, ATTN_NORM);
    cs_die1();
};

// Soldiers also fight other teams: the nearest visible monster of another class becomes the target.
void() cs_scan =
{
    local entity m, best;
    local float d, bd;

    if (time < self.sigf_scan_t)
        return;
    self.sigf_scan_t = time + 1 + random();
    if (self.enemy.health > 0 && self.enemy.classname != "player" && visible(self.enemy))
        return;
    best = world;
    bd = 1000;
    m = findradius(self.origin, 1000);
    while (m)
    {
        if (m != self && m.health > 0 && (m.flags & FL_MONSTER) && m.classname != self.classname
            && m.classname != "sigf_bomb")
        {
            traceline(self.origin + '0 0 16', m.origin + '0 0 16', TRUE, self);
            if (trace_fraction == 1)
            {
                d = vlen(m.origin - self.origin);
                if (d < bd)
                {
                    bd = d;
                    best = m;
                }
            }
        }
        m = m.chain;
    }
    if (best)
    {
        if (self.enemy.classname == "player")
            self.oldenemy = self.enemy;
        self.enemy = best;
        HuntTarget();
    }
};

void(float team) cs_init =
{
    precache_model("progs/sigf_terro.mdl");
    precache_model("progs/sigf_ct.mdl");
    precache_model("progs/sigf_cash.mdl");
    precache_model("progs/h_player.mdl");
    precache_model("progs/gib1.mdl");
    precache_model("progs/gib2.mdl");
    precache_model("progs/gib3.mdl");
    precache_sound("soldier/pain1.wav");
    precache_sound("soldier/pain2.wav");
    precache_sound("soldier/death1.wav");
    precache_sound("player/udeath.wav");
    precache_sound("sigf/ak.wav");
    precache_sound("sigf/v_fire.wav");
    precache_sound("sigf/v_go.wav");
    precache_sound("sigf/rico.wav");
    self.sigf_team = team;
    self.solid = SOLID_SLIDEBOX;
    self.movetype = MOVETYPE_STEP;
    if (team == 1)
    {
        self.classname = "sigf_t";
        setmodel(self, "progs/sigf_terro.mdl");
        self.health = 90;
    }
    else
    {
        self.classname = "sigf_ct";
        setmodel(self, "progs/sigf_ct.mdl");
        self.health = 120;
    }
    setsize(self, '-18 -18 -24', '18 18 46');
    self.th_stand = cs_stand1;
    self.th_walk = cs_walk1;
    self.th_run = cs_run1;
    self.th_missile = cs_attack;
    self.th_pain = cs_pain;
    self.th_die = cs_die;
    walkmonster_start();
};

void() monster_sigf_t = { if (deathmatch) { remove(self); return; } cs_init(1); };
void() monster_sigf_ct = { if (deathmatch) { remove(self); return; } cs_init(2); };

// monster_army and monster_enforcer of the maps land here: two Terrorists for every Counter-Terrorist
void() monster_sigf_cs =
{
    if (deathmatch)
    {
        remove(self);
        return;
    }
    sigf_alt = sigf_alt + 1;
    if (sigf_alt > 2)
    {
        sigf_alt = 0;
        cs_init(2);
    }
    else
        cs_init(1);
};

// ---------- the bomb ----------
void() sigf_bomb_think =
{
    local float remaining, interval;

    remaining = self.sigf_fuse_end - time;
    // only a target while the player can see it: the demo player would walk into walls toward a hidden one
    traceline(self.enemy.origin + self.enemy.view_ofs, self.origin + '0 0 -12', TRUE, self.enemy);
    if (trace_fraction == 1)
        self.flags = self.flags | FL_MONSTER;
    else if (self.flags & FL_MONSTER)
        self.flags = self.flags - FL_MONSTER;
    if (self.enemy.classname == "player" && time > self.sigf_msg_t)
    {
        self.sigf_msg_t = time + 1;
        if (self.sigf_fuse_total - remaining < 3.2)
            centerprint(self.enemy, "BOMB PLANTED\nShoot it to defuse!");
        else if (remaining < 6)
        {
            centerprint(self.enemy, "C4 EXPLODES IN\n");
            sprint(self.enemy, "C4: ");
            sprint(self.enemy, ftos(floor(remaining) + 1));
            sprint(self.enemy, "\n");
        }
    }
    if (remaining <= 0)
    {
        T_RadiusDamage(self, self, 260, world);
        WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
        WriteByte(MSG_BROADCAST, TE_EXPLOSION);
        WriteCoord(MSG_BROADCAST, self.origin_x);
        WriteCoord(MSG_BROADCAST, self.origin_y);
        WriteCoord(MSG_BROADCAST, self.origin_z);
        WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
        WriteByte(MSG_BROADCAST, TE_EXPLOSION);
        WriteCoord(MSG_BROADCAST, self.origin_x + 40);
        WriteCoord(MSG_BROADCAST, self.origin_y);
        WriteCoord(MSG_BROADCAST, self.origin_z + 30);
        WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
        WriteByte(MSG_BROADCAST, TE_TAREXPLOSION);
        WriteCoord(MSG_BROADCAST, self.origin_x);
        WriteCoord(MSG_BROADCAST, self.origin_y);
        WriteCoord(MSG_BROADCAST, self.origin_z);
        sound(self, CHAN_WEAPON, "weapons/r_exp3.wav", 1, ATTN_NONE);
        sound(self, CHAN_VOICE, "sigf/v_twin.wav", 1, ATTN_NONE);
        centerprint(self.enemy, "TERRORISTS WIN\nThe bomb exploded");
        bprint("*** Terrorists win! ***\n");
        self.enemy.sigf_money = self.enemy.sigf_money - 500;
        if (self.enemy.sigf_money < 0) self.enemy.sigf_money = 0;
        remove(self);
        return;
    }
    if (self.sigf_phase == 0)
    {
        // beep and flash; the beeps speed up as the fuse burns down
        self.sigf_phase = 1;
        sound(self, CHAN_VOICE, "sigf/beep.wav", 1, ATTN_NORM);
        self.effects = EF_BRIGHTLIGHT;
        particle(self.origin + '0 0 -4', '0 0 60', 250, 30);
        particle(self.origin + '0 0 20', '0 0 90', 79, 30);
        particle(self.origin + '0 0 44', '0 0 120', 250, 30);
        self.nextthink = time + 0.12;
    }
    else
    {
        self.sigf_phase = 0;
        self.effects = 0;
        interval = 0.12 + 0.9 * (remaining / self.sigf_fuse_total);
        self.nextthink = time + interval;
    }
};

void(entity attacker, float damage) sigf_bomb_pain =
{
    particle(self.origin, '0 0 60', 8, 10);
    sound(self, CHAN_BODY, "sigf/dink.wav", 1, ATTN_NORM);
};

void() sigf_bomb_die =
{
    self.takedamage = DAMAGE_NO;
    self.effects = 0;
    self.nextthink = time + 0.2;
    self.think = SUB_Remove;
    sound(self, CHAN_VOICE, "sigf/v_defused.wav", 1, ATTN_NONE);
    particle(self.origin, '0 0 80', 8, 60);
    bprint("*** The bomb has been defused! ***\n");
    if (self.enemy.classname == "player")
    {
        centerprint(self.enemy, "BOMB DEFUSED\n+$3500");
        self.enemy.sigf_money = self.enemy.sigf_money + 3500;
        stuffcmd(self.enemy, "bf\n");
    }
    sigf_drop_cash(self.origin, 500);
};

// the bomb is shot at to defuse it (the player's bullets call T_Damage): it is a "monster" so aim and the demo find it
void() sigf_bomb_spawn =
{
    local entity p;
    precache_model("progs/sigf_bomb.mdl");
    precache_sound("sigf/beep.wav");
    precache_sound("sigf/dink.wav");
    precache_sound("sigf/v_twin.wav");
    precache_sound("sigf/v_defused.wav");
    precache_sound("sigf/v_planted.wav");
    precache_sound("weapons/r_exp3.wav");
    self.classname = "sigf_bomb";
    self.solid = SOLID_SLIDEBOX;
    self.movetype = MOVETYPE_STEP;
    self.flags = self.flags | FL_MONSTER;
    self.takedamage = DAMAGE_AIM;
    self.health = sigf_bomb_hp;
    setmodel(self, "progs/sigf_bomb.mdl");
    setsize(self, '-36 -36 -24', '36 36 10');
    self.th_stand = sigf_bomb_idle;
    self.th_walk = sigf_bomb_idle;
    self.th_run = sigf_bomb_idle;
    self.th_pain = sigf_bomb_pain;
    self.th_die = sigf_bomb_die;
    self.frame = 0;
    self.angles = '0 30 0';
    self.sigf_fuse_total = sigf_bomb_fuse;
    self.sigf_fuse_end = time + self.sigf_fuse_total;
    self.sigf_phase = 0;
    self.think = sigf_bomb_think;
    self.nextthink = time + 0.5;
    p = find(world, classname, "player");
    self.enemy = p;
    sound(self, CHAN_VOICE, "sigf/v_planted.wav", 1, ATTN_NONE);
    bprint("*** The bomb has been planted! Shoot it to defuse! ***\n");
    centerprint(p, "BOMB PLANTED\nShoot it to defuse!");
    droptofloor();
};

// plants the bomb in the roomiest direction around the player (self), 60% of the way to the wall
void() sigf_plant =
{
    local entity e, oself;
    local float a, d, bd, ba;
    local vector start, org;

    start = self.origin + '0 0 16';
    bd = -1;
    ba = 0;
    a = -90;
    while (a <= 90)
    {
        makevectors('0 1 0' * (self.v_angle_y + a));
        traceline(start, start + v_forward * 520, TRUE, self);
        d = trace_fraction * 520;
        if (a < 0) d = d + 0 - a * 0.3;
        else d = d - a * 0.3;
        if (d > bd)
        {
            bd = d;
            ba = a;
        }
        a = a + 30;
    }
    makevectors('0 1 0' * (self.v_angle_y + ba));
    traceline(start, start + v_forward * 520, TRUE, self);
    org = start + v_forward * (trace_fraction * 520 * 0.5);
    traceline(org, org - '0 0 200', TRUE, self);
    org = trace_endpos + '0 0 24';
    e = spawn();
    e.classname = "sigf_bomb";
    setorigin(e, org);
    oself = self;
    self = e;
    sigf_bomb_spawn();
    self = oself;
};

// the yaw with the most open floor in front of the player (demo start: never stare at a wall)
float() sigf_open_yaw =
{
    local float a, d, bd, ba;
    local vector start;
    start = self.origin + '0 0 16';
    bd = -1;
    ba = 0;
    a = 0;
    while (a < 360)
    {
        makevectors('0 1 0' * a);
        traceline(start, start + v_forward * 1200, TRUE, self);
        d = trace_fraction;
        if (d > bd)
        {
            bd = d;
            ba = a;
        }
        a = a + 20;
    }
    return ba;
};

// like SIGF_SpawnAhead, but never into a wall: it turns the player toward open floor when the view is blocked
entity(string cls, void() spawnfunc, float dist, float side) sigf_spawn_open =
{
    local float ya, use;
    local vector start, org;
    local entity e, oself;

    start = self.origin + '0 0 16';
    makevectors('0 1 0' * self.v_angle_y);
    traceline(start, start + v_forward * 420, TRUE, self);
    ya = self.v_angle_y;
    if (trace_fraction < 0.7)
    {
        ya = sigf_open_yaw();
        self.angles_y = ya;
        self.fixangle = 1;
    }
    makevectors('0 1 0' * ya);
    traceline(start, start + v_forward * dist, TRUE, self);
    use = dist * trace_fraction * 0.8;
    org = start + v_forward * use + v_right * side * (use / dist);
    traceline(start, org, TRUE, self);
    if (trace_fraction < 1)
        org = start + v_forward * use;
    traceline(org, org - '0 0 300', TRUE, self);
    org = trace_endpos + '0 0 26';
    e = spawn();
    e.classname = cls;
    setorigin(e, org);
    e.angles_y = ya + 180;
    oself = self;
    self = e;
    spawnfunc();
    self = oself;
    return e;
};

float() sigf_count_cs =
{
    local entity m;
    local float n;
    n = 0;
    m = find(world, classname, "sigf_t");
    while (m) { if (m.health > 0) n = n + 1; m = find(m, classname, "sigf_t"); }
    m = find(world, classname, "sigf_ct");
    while (m) { if (m.health > 0) n = n + 1; m = find(m, classname, "sigf_ct"); }
    return n;
};

// ---------- player rules, every frame ----------
void() sigf_player_tick =
{
    local float a;

    if (self.classname != "player")
        return;
    if (!self.sigf_init)
    {
        self.sigf_init = 1;
        self.sigf_money = 800;
        self.sigf_next_bomb = time + 70;
        if (SIGF_Mode() != 0)
        {
            self.angles_y = sigf_open_yaw(); self.sigf_goal_yaw = self.angles_y;
            self.fixangle = 1;
        }
        stuffcmd(self, "fog 0.07 0.78 0.62 0.38\n");           // dusty yellow haze: de_dust
    }
    // demo: start in the open sunken arena of the first map (soldiers and the bomb read best there)
    if (SIGF_Mode() != 0 && SIGF_Mode() != 3 && !self.sigf_moved && time > 0.4 && mapname == "lq_e0m1")
    {
        self.sigf_moved = 1;
        setorigin(self, '256 2180 -30');
        self.angles_y = sigf_open_yaw(); self.sigf_goal_yaw = self.angles_y;
        self.fixangle = 1;
        self.v_angle_y = self.angles_y;
        centerprint(self, "ROUND 1 - FIGHT!\nTerrorists vs Counter-Terrorists");
        sigf_spawn_open("monster_sigf_t", monster_sigf_t, 230, -70);
        sigf_spawn_open("monster_sigf_ct", monster_sigf_ct, 250, 70);
        sigf_spawn_open("monster_sigf_t", monster_sigf_t, 320, 0);
    }
    // demo: never face a wall, and always keep a few soldiers close in view
    if (SIGF_Mode() != 0 && SIGF_Mode() != 3 && time > 1.2 && time > self.sigf_keep_t)
    {
        self.sigf_keep_t = time + 0.4;
        makevectors('0 1 0' * self.v_angle_y);
        traceline(self.origin + '0 0 16', self.origin + '0 0 16' + v_forward * 700, TRUE, self);
        if (trace_fraction < 0.8)
        {
            self.angles_y = sigf_open_yaw(); self.sigf_goal_yaw = self.angles_y;
            self.fixangle = 1;
        }
        if (time > self.sigf_spawn_t && sigf_count_cs() < 4)
        {
            self.sigf_spawn_t = time + 1.8;
            if (random() < 0.5)
                sigf_spawn_open("monster_sigf_t", monster_sigf_t, 220, crandom() * 120);
            else
                sigf_spawn_open("monster_sigf_ct", monster_sigf_ct, 220, crandom() * 120);
        }
    }
    // flashbang: the screen goes white and fades
    if (self.sigf_flash_until > time)
    {
        if (time > self.sigf_flash_cmd)
        {
            self.sigf_flash_cmd = time + 0.1;
            a = (self.sigf_flash_until - time) * 200;
            if (a > 255) a = 255;
            stuffcmd(self, "v_cshift 255 255 255 ");
            stuffcmd(self, ftos(a));
            stuffcmd(self, "\n");
        }
    }
    else if (self.sigf_flash_until)
    {
        self.sigf_flash_until = 0;
        stuffcmd(self, "v_cshift 0 0 0 0\n");
    }
    // auto-buy: kevlar when rich and unarmored
    if (self.sigf_money >= 1000 && self.armorvalue < 30)
    {
        self.sigf_money = self.sigf_money - 650;
        self.armorvalue = 100;
        self.armortype = 0.3;
        self.items = self.items - (self.items & (IT_ARMOR1 | IT_ARMOR2 | IT_ARMOR3)) + IT_ARMOR1;
        sound(self, CHAN_ITEM, "sigf/cash.wav", 1, ATTN_NORM);
        centerprint(self, "Bought Kevlar + Helmet\n-$650");
    }
    // normal play: the Terrorists plant a bomb now and then
    if (SIGF_Mode() == 0 && time > self.sigf_next_bomb)
    {
        self.sigf_next_bomb = time + 90;
        sigf_plant();
    }
};

// ---------- the three hooks ----------
void() SIGF_Precache =
{
    precache_model("progs/sigf_cash.mdl");
    precache_model("progs/sigf_bomb.mdl");
    precache_model("progs/sigf_nade.mdl");
    precache_model("progs/sigf_flashnade.mdl");
    precache_sound("sigf/ak.wav");
    precache_sound("sigf/awp.wav");
    precache_sound("sigf/deagle.wav");
    precache_sound("sigf/beep.wav");
    precache_sound("sigf/dink.wav");
    precache_sound("sigf/flash.wav");
    precache_sound("sigf/cash.wav");
    precache_sound("sigf/rico.wav");
    precache_sound("sigf/v_fire.wav");
    precache_sound("sigf/v_twin.wav");
    precache_sound("sigf/v_ctwin.wav");
    precache_sound("sigf/v_planted.wav");
    precache_sound("sigf/v_defused.wav");
    precache_sound("sigf/v_spot.wav");
    precache_sound("sigf/v_go.wav");
    precache_sound("sigf/v_head.wav");
    precache_sound("weapons/bounce.wav");
    precache_sound("weapons/grenade.wav");
    precache_sound("weapons/r_exp3.wav");
    SIGF_Preload("monster_sigf_t", monster_sigf_t);
    SIGF_Preload("monster_sigf_ct", monster_sigf_ct);
    SIGF_Preload("monster_ogre", monster_ogre);
    SIGF_Preload("monster_demon1", monster_demon1);
    SIGF_Preload("monster_knight", monster_knight);
};

void(float w) sigf_pick =
{
    self.weapon = w;
    W_SetCurrentAmmo();
};

void(float wave) SIGF_DemoWave =
{
    if (wave == 0)
    {
        self.items = self.items | IT_SHOTGUN | IT_SUPER_SHOTGUN | IT_NAILGUN | IT_SUPER_NAILGUN | IT_GRENADE_LAUNCHER | IT_ROCKET_LAUNCHER;
        self.ammo_shells = 50;
        self.ammo_nails = 150;
        self.ammo_rockets = 25;
        sigf_pick(IT_NAILGUN);
        centerprint(self, "COUNTER-STRIKE 1.6\nTAKEOVER\n\nTerrorists vs Counter-Terrorists");
        sigf_spawn_open("monster_sigf_t", monster_sigf_t, 260, -80);
        sigf_spawn_open("monster_sigf_ct", monster_sigf_ct, 280, 80);
        sigf_spawn_open("monster_sigf_t", monster_sigf_t, 340, 0);
        return;
    }
    if (wave == 1)
    {
        sigf_pick(IT_SUPER_SHOTGUN);
        centerprint(self, "FLASHBANG OUT!");
        makevectors(self.v_angle);
        sigf_throw(world, self.origin + '0 0 40' + v_forward * 90, v_forward * 40 + '0 0 120', 1).nextthink = time + 0.9;
        sigf_spawn_open("monster_sigf_ct", monster_sigf_ct, 400, -60);
        sigf_spawn_open("monster_sigf_t", monster_sigf_t, 460, 60);
        sigf_spawn_open("monster_sigf_t", monster_sigf_t, 520, -20);
        return;
    }
    if (wave == 2)
    {
        sigf_pick(IT_NAILGUN);
        sigf_bomb_hp = 1800;                      // too tough to defuse in time: it blows up
        sigf_bomb_fuse = 12;
        sigf_plant();
        sigf_spawn_open("monster_sigf_t", monster_sigf_t, 450, 100);
        return;
    }
    if (wave == 3)
    {
        sigf_pick(IT_SHOTGUN);
        sigf_spawn_open("monster_sigf_ct", monster_sigf_ct, 400, -80);
        sigf_spawn_open("monster_sigf_t", monster_sigf_t, 450, 40);
        sigf_spawn_open("monster_sigf_ct", monster_sigf_ct, 500, 0);
        return;
    }
    if (wave == 4)
    {
        sigf_pick(IT_ROCKET_LAUNCHER);
        sigf_spawn_open("monster_sigf_t", monster_sigf_t, 380, -70);
        sigf_spawn_open("monster_sigf_ct", monster_sigf_ct, 440, 70);
        sigf_spawn_open("monster_sigf_ct", monster_sigf_ct, 500, 0);
        return;
    }
    if (wave == 5)
    {
        sigf_pick(IT_GRENADE_LAUNCHER);
        sigf_spawn_open("monster_ogre", monster_ogre, 520, 0);
        sigf_spawn_open("monster_sigf_t", monster_sigf_t, 440, -80);
        return;
    }
    if (wave == 6)
    {
        sigf_pick(IT_SUPER_NAILGUN);
        sigf_bomb_hp = 400;                       // this one gets defused
        sigf_bomb_fuse = 20;
        sigf_plant();
        sigf_spawn_open("monster_sigf_ct", monster_sigf_ct, 400, 70);
        sigf_spawn_open("monster_sigf_t", monster_sigf_t, 440, -70);
        return;
    }
    sigf_pick(IT_NAILGUN);
    sigf_spawn_open("monster_sigf_t", monster_sigf_t, 420, -60);
    if (wave & 1)
        sigf_spawn_open("monster_sigf_ct", monster_sigf_ct, 440, 60);
    else
        sigf_spawn_open("monster_demon1", monster_demon1, 520, 0);
};

// killer, feed, rewards
void(entity targ, entity attacker) SIGF_OnKilled =
{
    local float reward;

    if (targ.classname == "player")
        return;
    if (!(targ.flags & FL_MONSTER))
        return;
    if (targ.classname == "sigf_bomb")
        return;
    // kill feed
    bprint(sigf_name(attacker));
    bprint(" [");
    bprint(sigf_wname(attacker));
    bprint("] ");
    bprint(sigf_name(targ));
    if (targ.sigf_hs)
        bprint("  (HEADSHOT)");
    bprint("\n");
    reward = 300;
    if (targ.sigf_hs)
        reward = 450;
    sigf_drop_cash(targ.origin, reward);
    if (attacker.classname == "player")
    {
        if (targ.sigf_hs)
        {
            centerprint(attacker, "HEADSHOT!\n*DINK*");
            sound(attacker, CHAN_VOICE, "sigf/v_head.wav", 1, ATTN_NORM);
            stuffcmd(attacker, "bf\n");
        }
        attacker.sigf_pkills = attacker.sigf_pkills + 1;
        if (attacker.sigf_pkills >= 6)
        {
            attacker.sigf_pkills = 0;
            sigf_round = sigf_round + 1;
            attacker.sigf_money = attacker.sigf_money + 3250;
            centerprint(attacker, "COUNTER-TERRORISTS WIN\nRound won  +$3250");
            bprint("*** Counter-Terrorists win the round! ***\n");
            sound(attacker, CHAN_VOICE, "sigf/v_ctwin.wav", 1, ATTN_NONE);
        }
    }
};
