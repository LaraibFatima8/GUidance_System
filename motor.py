import pygame
import serial

# --- Serial Setup ---
try:
    ser = serial.Serial('COM7', 9600, timeout=1)
except:
    ser = None
    print("[WARNING] Serial port COM8 could not be opened.")

# --- Constants ---
WIDTH, HEIGHT = 1280, 720
SERVO_MIN = 26      # Approx 0°
SERVO_MAX = 230     # Approx 180°
SERVO_RANGE = SERVO_MAX - SERVO_MIN

GRID_DIV = 10       # Grid divisions


# --- Pygame Setup ---
pygame.init()
font = pygame.font.SysFont("Arial", 20)
screen = pygame.display.set_mode((WIDTH, HEIGHT))
pygame.display.set_caption("Scaled UART Servo Controller")
clock = pygame.time.Clock()

# --- Object State ---
x, y = WIDTH // 2, HEIGHT // 2
speed = 5
auto_sweep = False
sweep_dir = 1
running = True

# --- Main Loop ---
while running:
    screen.fill((20, 20, 20))  # Background color

    # --- Grid Drawing ---
    for i in range(GRID_DIV + 1):
        pygame.draw.line(screen, (50, 50, 50), (i * WIDTH // GRID_DIV, 0), (i * WIDTH // GRID_DIV, HEIGHT))
        pygame.draw.line(screen, (50, 50, 50), (0, i * HEIGHT // GRID_DIV), (WIDTH, i * HEIGHT // GRID_DIV))

    # --- Event Handling ---
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False
        elif event.type == pygame.KEYDOWN:
            if event.key == pygame.K_a:
                auto_sweep = not auto_sweep

    # --- Key Controls ---
    keys = pygame.key.get_pressed()
    if keys[pygame.K_LEFT]:
        x = max(0, x - speed)
    if keys[pygame.K_RIGHT]:
        x = min(WIDTH - 1, x + speed)
    if keys[pygame.K_UP]:
        y = max(0, y - speed)
    if keys[pygame.K_DOWN]:
        y = min(HEIGHT - 1, y + speed)
    if keys[pygame.K_SPACE]:
        x = 0
    if keys[pygame.K_RETURN]:
        x = WIDTH - 1

    # --- Auto Sweep ---
    if auto_sweep:
        x += sweep_dir
        if x >= WIDTH:
            x = WIDTH
            sweep_dir = -1
        elif x <= 0:
            x = 0
            sweep_dir = 1

    # --- Scale to Servo Range ---
    scaled_x = int(SERVO_MIN + (x / WIDTH) * SERVO_RANGE)
    scaled_y = int(SERVO_MIN + (y / HEIGHT) * SERVO_RANGE)

    scaled_x = max(SERVO_MIN, min(SERVO_MAX, scaled_x))
    scaled_y = max(SERVO_MIN, min(SERVO_MAX, scaled_y))

    # --- Send UART ---
    if ser and ser.is_open:
        try:
            ser.write(bytes([scaled_y, scaled_x]))
            print(f"Sent: Y={scaled_y}, X={scaled_x}")
  # Y then X
        except serial.SerialException as e:
            print(f"[UART ERROR] {e}")

    # --- Visual Position ---
    draw_x = int(((scaled_x - SERVO_MIN) / SERVO_RANGE) * WIDTH)
    draw_y = int(((scaled_y - SERVO_MIN) / SERVO_RANGE) * HEIGHT)
    pygame.draw.circle(screen, (0, 255, 0), (draw_x, draw_y), 10)

    # --- Debug Info ---
    info_text = f"GUI X={x}, Y={y} | Servo X={scaled_x}, Y={scaled_y}"
    screen.blit(font.render(info_text, True, (255, 255, 255)), (10, 10))

    # --- Refresh ---
    pygame.display.flip()
    clock.tick(30)

# --- Cleanup ---
if ser:
    ser.close()
pygame.quit()
