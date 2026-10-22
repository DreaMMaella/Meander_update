#!/usr/bin/env bash
# Patch volume_controller to handle missing Master mixer (PipeWire) without SEGV
# Without this, getVolume on Arch/PipeWire crashes with SIGSEGV when Master not found
set -e
FILE="$HOME/.pub-cache/hosted/pub.dev/volume_controller-3.6.1/linux/volume_controller_plugin.cc"
if [ ! -f "$FILE" ]; then
  FILE=$(find "$HOME/.pub-cache/hosted/pub.dev" -path "*volume_controller*/linux/volume_controller_plugin.cc" | head -n1)
fi
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then echo "volume_controller not found"; exit 0; fi
if grep -q "AudioController not initialized.*getVolume" "$FILE"; then echo "already patched"; exit 0; fi
echo "Patching $FILE"
python3 << 'PY'
import pathlib, re
candidates = list(pathlib.Path.home().glob(".pub-cache/hosted/pub.dev/volume_controller-*/linux/volume_controller_plugin.cc"))
for p in candidates:
    t = p.read_text()
    old = """  if (strcmp(method, MethodName::getVolume) == 0)
  {
    response = get_volume(self->audioController);
  }
  else if (strcmp(method, MethodName::setVolume) == 0)
  {
    FlValue *arg = fl_value_lookup_string(args, MethodArgument::volume);
    double volume = fl_value_get_float(arg);

    response = set_volume(self->audioController, volume);
  }
  else if (strcmp(method, MethodName::isMuted) == 0)
  {
    response = is_muted(self->audioController);
  }
  else if (strcmp(method, MethodName::setMute) == 0)
  {
    FlValue *arg = fl_value_lookup_string(args, MethodArgument::isMute);
    bool mute = fl_value_get_bool(arg);
    response = set_mute(self->audioController, mute);
  }"""
    new = """  if (strcmp(method, MethodName::getVolume) == 0)
  {
    if (!self->audioController) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("Error", "AudioController not initialized", NULL));
    } else {
      response = get_volume(self->audioController);
    }
  }
  else if (strcmp(method, MethodName::setVolume) == 0)
  {
    if (!self->audioController) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("Error", "AudioController not initialized", NULL));
    } else {
      FlValue *arg = fl_value_lookup_string(args, MethodArgument::volume);
      double volume = fl_value_get_float(arg);

      response = set_volume(self->audioController, volume);
    }
  }
  else if (strcmp(method, MethodName::isMuted) == 0)
  {
    if (!self->audioController) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("Error", "AudioController not initialized", NULL));
    } else {
      response = is_muted(self->audioController);
    }
  }
  else if (strcmp(method, MethodName::setMute) == 0)
  {
    if (!self->audioController) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("Error", "AudioController not initialized", NULL));
    } else {
      FlValue *arg = fl_value_lookup_string(args, MethodArgument::isMute);
      bool mute = fl_value_get_bool(arg);
      response = set_mute(self->audioController, mute);
    }
  }"""
    if old in t:
        t = t.replace(old, new)
        p.write_text(t)
        print(f"patched {p}")
PY
echo "Patched volume_controller"
