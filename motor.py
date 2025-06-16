import pygame
import serial

# --- Serial Setup ---
# Change 'COM8' to your correct port
ser = serial.Serial('COM8', 9600, timeout=1)

# --- Pygame Setup ---
pygame.init()
screen = pygame.display.set_mode((127, 127))
pygame.display.set_caption("UART Servo Controller")
clock = pygame.time.Clock()

# --- Object State ---
x, y = 64, 64
speed = 1
auto_sweep = False
sweep_dir = 1
running = True

# --- Main Loop ---
while running:
    screen.fill((0, 0, 0))

    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False

    # --- Key Controls ---
    keys = pygame.key.get_pressed()
    if keys[pygame.K_LEFT]:
        x = max(0, x - speed)
    if keys[pygame.K_RIGHT]:
        x = min(127, x + speed)
    if keys[pygame.K_UP]:
        y = max(0, y - speed)
    if keys[pygame.K_DOWN]:
        y = min(127, y + speed)

    # Manual jump test
    if keys[pygame.K_SPACE]:
        x = 0
    if keys[pygame.K_RETURN]:
        x = 127

    # Toggle auto-sweep (press A key)
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False
        elif event.type == pygame.KEYDOWN:
            if event.key == pygame.K_a:
                auto_sweep = not auto_sweep

    if auto_sweep:
        x += sweep_dir
        if x >= 127:
            x = 127
            sweep_dir = -1
        elif x <= 0:
            x = 0
            sweep_dir = 1

    # --- Send X over UART ---
    try:
        ser.write(bytes([127-y]))  # two bytes per frame
 # Flip direction
  # only send 1 byte
    except serial.SerialException as e:
        print(f"[UART ERROR] {e}")

    # --- Draw Circle ---
    pygame.draw.circle(screen, (0, 127, 0), (x, y), 4)

    # --- Update Display ---
    pygame.display.flip()
    clock.tick(30)  # Faster refresh (30 FPS)

# --- Cleanup ---
ser.close()
pygame.quit()
