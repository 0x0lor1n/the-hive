# Deliberately touches the unfetchable input. Evaluating THIS must fail --
# that is the negative control proving the test is honest.
{inputs, ...}: {
  forcesTheFetch = inputs.heavyThing or "cell-flake-outputs-missing";
}
