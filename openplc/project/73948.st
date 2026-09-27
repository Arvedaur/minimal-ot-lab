(*
  Asama 2 - Ruzgar turbini proses simulasyonu (Structured Text)
  Bolum 6 register haritasina karsilik gelir:

    %MW0  WindSpeed            (85  = 8.5 m/s)
    %MW1  RotorSpeed           (145 = 14.5 rpm)
    %MW2  ActivePower          (2350 kW)
    %MW3  GeneratorTemperature (620 = 62.0 C)
    %MW4  OperatingState       (0/1/2/3)
    %QX0.0 TurbineRunning      (BOOL)
    %QX0.1 GeneralAlarm        (BOOL)

  Bu program compile edildikten sonra OpenPLC web UI "Hardware" sayfasinda
  bu adresler Modbus TCP :502 uzerinden holding register / coil olarak
  disari acilir (bkz. README.md Asama 2).
*)

PROGRAM wind_turbine_sim
  VAR
    (* AT %MW/%QX ile located (Modbus'a acilan) degiskenler - bunlar olmadan
       degerler sadece PLC icinde kalir, Monitoring/Modbus'ta GORUNMEZ. *)
    wind_speed    AT %MW0  : INT := 85;    (* 8.5 m/s baslangic *)
    rotor_speed   AT %MW1  : INT := 0;
    active_power  AT %MW2  : INT := 0;
    gen_temp      AT %MW3  : INT := 400;   (* 40.0 C baslangic *)
    op_state      AT %MW4  : INT := 0;     (* 0=STOPPED 1=STARTING 2=RUNNING 3=FAULT *)
    running       AT %QX0.0 : BOOL := FALSE;
    alarm         AT %QX0.1 : BOOL := FALSE;

    tick          : DINT := 0;
    direction     : INT := 1;
  END_VAR

  tick := tick + 1;

  (* Ruzgar hizini 4.0 - 18.0 m/s araliginda yavasca salinacak sekilde uret *)
  IF wind_speed >= 180 THEN
    direction := -1;
  ELSIF wind_speed <= 40 THEN
    direction := 1;
  END_IF;
  IF tick MOD 20 = 0 THEN
    wind_speed := wind_speed + direction;
  END_IF;

  (* Basit durum makinesi *)
  IF wind_speed < 30 THEN
    op_state := 0;   (* STOPPED - ruzgar cok az *)
    running  := FALSE;
  ELSIF op_state = 0 AND wind_speed >= 30 THEN
    op_state := 1;   (* STARTING *)
  ELSIF op_state = 1 THEN
    op_state := 2;   (* RUNNING *)
    running  := TRUE;
  END_IF;

  (* Rotor hizi ve guc ruzgar hizina bagli (kabaca dogrusal, sadelestirilmis) *)
  IF running THEN
    rotor_speed  := wind_speed * 2;              (* 8.5 m/s -> 17 -> 14.5 rpm civari *)
    active_power := (wind_speed * wind_speed) / 3; (* basit kubik yerine sadelestirilmis egri *)
  ELSE
    rotor_speed  := 0;
    active_power := 0;
  END_IF;

  (* Jenerator sicakligi yuke bagli yavas isinma/sogumadan olusur *)
  IF running AND gen_temp < 750 THEN
    gen_temp := gen_temp + 1;
  ELSIF NOT running AND gen_temp > 400 THEN
    gen_temp := gen_temp - 1;
  END_IF;

  (* Alarm: asiri sicaklik *)
  IF gen_temp > 700 THEN
    alarm    := TRUE;
    op_state := 3;   (* FAULT *)
  ELSE
    alarm := FALSE;
  END_IF;

END_PROGRAM


CONFIGURATION Config0
  RESOURCE Res0 ON PLC
    TASK task0(INTERVAL := T#100ms,PRIORITY := 0);
    PROGRAM instance0 WITH task0 : wind_turbine_sim;
  END_RESOURCE
END_CONFIGURATION
