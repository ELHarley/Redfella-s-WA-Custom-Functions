-- UNIT_POWER_FREQUENT, SPELL_UPDATE_COOLDOWN, SPELL_UPDATE_CHARGES, PLAYER_TARGET_CHANGED, UNIT_SPELLCAST_SUCCEEDED

function ()
    if not WA_Redfellas_Rot_BDK_Enabled or UnitOnTaxi("player") or not UnitCanAttack("player", "target") then
        return false
    end

    local now = GetTime()

    if now < aura_env.lastUpdate + aura_env.updateInterval then
        return true
    end

    aura_env.lastUpdate = now

    local targets = aura_env.targets
    local talentList = aura_env.talents
    local talented = aura_env.talented
    local abilities = aura_env.abilities
    local abilityNames = aura_env.abilityNames
    local cooldowns = aura_env.cooldowns
    local charges = aura_env.charges
    local chargeTime = aura_env.chargeTime
    local chargedAbilities = aura_env.chargedAbilities
    local chargesMax = aura_env.chargesMax
    local buffList = aura_env.buffs
    local buffNames = aura_env.buffNames
    local buffRemains = aura_env.buffRemains
    local debuffList = aura_env.debuffs
    local debuffNames = aura_env.debuffNames
    local debuffRemains = aura_env.debuffRemains
    local chargeCt = aura_env.chargeCt
    local cdLeft = aura_env.cdLeft

    local runic_power = UnitPower("player")
    local health_percentage = math.ceil( (UnitHealth("player") / UnitHealthMax("player") * 100) )
    local missing_health_percentage = 100 - health_percentage

    for k,v in pairs( targets ) do
        if now - v > aura_env.targetWipeInterval then
            targets[k] = nil
            aura_env.targetCount = max(0, aura_env.targetCount - 1)
        end
    end

    local gcdStart, gcdDuration = GetSpellCooldown(61304)
    local gcd = gcdStart + gcdDuration

    -- if GCD is active, we'll just advance to the end of the GCD.
    now = max( now, gcd )

    -- if the GCD isn't active, calculate what the GCD should be.
    if gcdDuration == 0 then
        gcdDuration = max( 1, 1.5 / ( 1 + ( GetHaste() / 100 ) ) )
    end

    -- Get active talents.
    for k,v in pairs( talentList ) do
        talented[ k ] = select(4, GetTalentInfo( unpack( v ) ) )
    end

    -- Grab ability CDs.
    for k,v in pairs( abilities ) do
        local start, duration = GetSpellCooldown(v)
        cooldowns[ k ] = select(2, IsUsableSpell(v)) and 999 or max( 0, start + duration - now )
    end

    -- Check # of charges.
    for k,v in pairs( chargedAbilities ) do
        local c, maxCharges, start, duration = GetSpellCharges(v)
        charges[ k ] = min( maxCharges, c + ( max(0, 1 - ( start + duration - now) / duration ) ) )
        chargeTime[ k ] = duration
        chargesMax[ k ] = maxCharges
    end

    -- Check if buffs are up.
    for k,v in pairs( buffList ) do
        local _, _, _, _, _, _, expires = UnitBuff("player", buffNames[ v ] )

        buffRemains[ k ] = 0

        if expires then
            if expires == 0 then
                buffRemains[ k ] = 10 -- No real duration, i.e. Fury of Air.
            else
                buffRemains[ k ] = expires - now
            end
        end
    end

    -- Check if debuffs are up.
    for k,v in pairs( debuffList ) do
        local _, _, _, _, _, _, expires = UnitDebuff("target", debuffNames[ v ] )
        debuffRemains[ k ] = expires and expires - now or 0
    end

    aura_env.lastRec = aura_env.recommended
    aura_env.recommended = 0
    aura_env.timeToReady = 10

    local spend_runes = false
    local danger_treshold = aura_env.danger_treshold
    local critical_treshold = aura_env.critical_treshold
    local ready = aura_env.ready
    local rec = aura_env.rec
    local runes = aura_env.runes_available()
    local ds_heal = aura_env.death_strike_heal()
    local bone_shield_stacks = aura_env.get_unit_aura_value(195181, 'count') or 0
    local death_strike_available = false
    local two_death_strikes_available = false
    local artifact_weapon = IsEquippedItem(128402)
    local blooddrinker_heal = aura_env.blooddrinker_heal()
    local consumption_heal = aura_env.consumption_heal()

    -- Easy booleans for how many death strikes we can pump out, we can actually do three with Ossuary but no need in this APL
    if (buffRemains.ossuary > 0 and runic_power >= 40) or runic_power >= 45 then death_strike_available = true end
    if (buffRemains.ossuary > 0 and runic_power >= 80) or runic_power >= 90 then two_death_strikes_available = true end

    -- Calculate time to soft-capping runes, we always, ALWAYS prefer to have three runes charging
    local time_to_3_runes = aura_env.time_to_x_runes(3)
    if time_to_3_runes <= 3.75 then spend_runes = true end

    -- Set rp cap for when to Death Strike even if it overheals
    local rp_cap_warning = 75
    if talented.ossuary then rp_cap_warning = 85 end
    local rp_high_cap = 100
    if talented.ossuary then rp_high_cap = 105 end

    -- Grab the expiration of Bone Shield aura
    local bone_shield_aura = select(7,UnitBuff("player",GetSpellInfo(195181))) or 0
    aura_env.bone_shield_danger = bone_shield_aura - GetTime()

    ---------------
    -- APL START --
    ---------------

    if not in_combat and ready( 'death_and_decay' ) then rec( 'death_and_decay' ) end

    -- DANGER TRESHOLD START
    -- Marrowrend if aura duration is less than 6 seconds
    if ready( 'marrowrend' ) and aura_env.bone_shield_danger > 0 and aura_env.bone_shield_danger < 6 and runes >= 2 then rec( 'marrowrend') end

    -- Cooldowns Enabled: below danger treshold (default: 55%)
    if WA_Redfellas_Rot_BDK_Def_CDs and health_percentage <= danger_treshold then
        -- Vampiric Embrace if: player is below critical treshold  --OR--  RP for two Death Strikes
        if ready( 'vampiric_blood' ) and health_percentage <= critical_treshold or two_death_strikes_available then rec( 'vampiric_blood' ) end
        -- Death Strike if: VE is active  --OR--  VE is on cooldown
        if ready( 'death_strike' ) and death_strike_available and (buffRemains.vampiric_blood > 0 or cooldowns.vampiric_blood > 0) then rec( 'death_strike' ) end
        -- Dancing Rune Weapon if: we can't Death Strike or VE, and VE isn't active
        if ready( 'dancing_rune_weapon' ) and not death_strike_available and cooldowns.vampiric_blood > 0 and buffRemains.vampiric_blood == 0 then rec( 'dancing_rune_weapon' ) end
        -- Prio RP generators when in danger
        if ready( 'death_and_decay' ) and (talented.rapid_decomposition or buffRemains.crimson_scourge >= 0 or aura_env.targetCount > 1) then rec( 'death_and_decay' ) end
        -- Marrowrend if: six or less Bone Shield stacks & Heart Strike if above
        if ready( 'marrowrend' ) and bone_shield_stacks <= 6 and runes >= 2 then rec( 'marrowrend') end
        if ready( 'heart_strike' ) and bone_shield_stacks >= 7 and runes >= 1 then rec( 'heart_strike') end
    end

    -- Cooldowns Disabled: below danger treshold (default: 55%)
    if not WA_Redfellas_Rot_BDK_Def_CDs and health_percentage <= danger_treshold then
        -- Death Strike
        if ready( 'death_strike' ) and death_strike_available then rec( 'death_strike' ) end
    end


    -- SELFHEALS IF: Will not overheal
    -- Consumption if: Artifact equipped
    if artifact_weapon and WA_Redfellas_Rot_BDK_Def_CDs and  ready( 'consumption') and missing_health_percentage >= consumption_heal then rec( 'consumption' ) end
    -- Blooddrinker if: talented & got runes
    if talented.blooddrinker and WA_Redfellas_Rot_BDK_Def_CDs and ready( 'blooddrinker' ) and missing_health_percentage >= blooddrinker_heal then rec( 'blooddrinker' ) end
    -- Death Strike if: not banking for Bonestorm
    if (not talented.bonestorm or (WA_Redfellas_Rot_BDK_Off_CDs and cooldowns.bonestorm > 0)) and ready( 'death_strike' ) and health_percentage > danger_treshold and missing_health_percentage >= ds_heal then rec( 'death_strike' ) end


    -- Blood Boil if: Blood Plague missing
    if ready( 'blood_boil' ) and charges.blood_boil >= 0 and debuffRemains.blood_plague == 0 then rec( 'blood_boil' ) end
    -- Death and Decay on CD if: using Rapid Decomposition talent  -- OR --  Crimson Scourge  -- OR --  fighting more than one target
    if ready( 'death_and_decay' ) and (talented.rapid_decomposition or buffRemains.crimson_scourge >= 0 or aura_env.targetCount > 1) then rec( 'death_and_decay' ) end
    -- Blood Boil if: over 1.5 charges available
    if ready( 'blood_boil' ) and chargeCt( 'blood_boil' ) >= 1.5 then rec( 'blood_boil' ) end
    -- Cooldowns Enabled: Dancing Rune Weapon to generate Bone Shield stacks
    if WA_Redfellas_Rot_BDK_Off_CDs and ready( 'dancing_rune_weapon' ) and bone_shield_stacks <= 4 and runes >= 2 then rec( 'dancing_rune_weapon' ) end
    -- Marrowrend if: missing Bone Shield
    if ready( 'marrowrend' ) and bone_shield_stacks == 0 and runes >= 2 then rec( 'marrowrend') end
    -- Bonestorm if: CD usage enabled, talented and 100+ RP
    if WA_Redfellas_Rot_BDK_Off_CDs and talented.bonestorm and ready( 'bonestorm' ) and runic_power >= 100 then rec( 'bonestorm' ) end
    -- Death Strike if: Need to spend RP and not talented Bonestorm / Bonestorm on CD
    if (not talented.bonestorm or (WA_Redfellas_Rot_BDK_Off_CDs and cooldowns.bonestorm > 0)) and ready( 'death_strike' ) and death_strike_available and runic_power >= rp_cap_warning then rec( 'death_strike' ) end
    -- Marrowrend if: Need 6 or more BS stacks and DRW active
    if ready( 'marrowrend' ) and buffRemains.dancing_rune_weapon > 0 and bone_shield_stacks <= 4 and runes >= 2 then rec( 'marrowrend') end

    -- If standing in DnD with Rapid Decomposition
    if talented.rapid_decomposition and buffRemains.death_and_decay > 0 then
        -- Fighting one target, keeping up Ossuary is optimal
        if talented.ossuary and aura_env.targetCount == 1 and ready( 'marrowrend' ) and bone_shield_stacks <= 5 and runes >= 2 then rec( 'marrowrend') end
        if talented.ossuary and aura_env.targetCount == 1 and ready( 'heart_strike' ) and bone_shield_stacks >= 6 and runes >= 1 then rec( 'heart_strike') end
        -- More than 1 target, HS will gain +3 (from main target) and +6 RP per cleave hit so using HS even if under 5 Bone Shield stacks is a net RP gain
        if talented.ossuary and aura_env.targetCount >= 2 and ready( 'marrowrend' ) and bone_shield_stacks <= 2 and runes >= 2 then rec( 'marrowrend') end
        if talented.ossuary and aura_env.targetCount >= 2 and ready( 'heart_strike' ) and bone_shield_stacks >= 3 and runes >= 1 then rec( 'heart_strike') end
    -- Regular rune spending: stay below 4 ready runes, but keep near it for next DnD
    else
        if ready( 'marrowrend' ) and bone_shield_stacks <= 6 and runes >= 2 then rec( 'marrowrend') end
        if ready( 'heart_strike' ) and bone_shield_stacks >= 7 and spend_runes then rec( 'heart_strike') end
    end

    -- Blood Tap if: time to 3 runes available is higher than 5 seconds
    if talented.blood_tap and ready ('blood_tap') and aura_env.time_to_x_runes(3) > 5 then rec( 'blood_tap' ) end
    -- Blood Boil if: really nothing else to cast
    if ready( 'blood_boil' ) then rec( 'blood_boil' ) end
    -- Blood Tap if: really nothing else to cast
    if talented.blood_tap and ready ('blood_tap') then rec( 'blood_tap' ) end

    ---------------
    -- APL END --
    ---------------



    if aura_env.timeToReady < 5 then
        if aura_env.showCooldownRing then
            local start, duration = GetSpellCooldown( aura_env.recommended )

            if not start or start == 0 then
                start, duration = GetSpellCooldown( 61304 )
            end

            WeakAuras.regions[aura_env.id].region.cooldown:SetReverse(aura_env.invertCooldownRing)
            WeakAuras.regions[aura_env.id].region.cooldown:SetCooldown(start, duration)
        end

        if aura_env.showRangeHighlight then
            local range = aura_env.recommended == 0 and 0 or  IsSpellInRange( abilityNames[ aura_env.recommended ] )

            if range == 0 then WeakAuras.regions[aura_env.id].region:Color(1, 0, 0, 1)
            else WeakAuras.regions[aura_env.id].region:Color(1, 1, 1, 1)
            end
        end
    else
        WeakAuras.regions[aura_env.id].region.cooldown:SetCooldown(0,0)
        WeakAuras.regions[aura_env.id].region:Color(1,1,1,1)
    end

    return true
end
