PROGRAM test_counter
  VAR
    counter AT %MW0 : INT := 0;
  END_VAR

  counter := counter + 1;

END_PROGRAM


CONFIGURATION Config0
  RESOURCE Res0 ON PLC
    TASK Main(INTERVAL := T#100ms,PRIORITY := 0);
    PROGRAM Inst0 WITH Main : test_counter;
  END_RESOURCE
END_CONFIGURATION
