const AppState = @import("state.zig").AppState;

pub fn bootstrap() AppState {
    return AppState.init();
}
