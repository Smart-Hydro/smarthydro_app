// Scroll hacia abajo pasa de cartel solo si el mapa ya está en la vista
// general. Si está acercado, la rueda sigue haciendo zoom.
export function boardTurns(deltaY, distance, overviewDistance, focused) {
  if (focused) return false;
  if (!(deltaY > 18)) return false;
  if (!(overviewDistance > 0)) return false;
  return distance >= overviewDistance * 0.92;
}
