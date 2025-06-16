import pygame
import serial

# Serial setup
try:
    ser = serial.Serial('COM7', 9600, timeout=1)
except:
    ser = None
    print("[WARNING] Serial port COM7 could not be opened.")

# GUI setup
WIDTH, HEIGHT = 900, 500
CENTER_X, CENTER_Y = WIDTH // 2, HEIGHT // 2
SERVO_CENTER = 90
GRID_DIV = 10

pygame.init()
font = pygame.font.SysFont("Arial", 20)
screen = pygame.display.set_mode((WIDTH, HEIGHT))
pygame.display.set_caption("Missile Prediction GUI (Corrected Quadrants)")
clock = pygame.time.Clock()

# Object position
x, y = CENTER_X, CENTER_Y
speed = 5
auto_sweep = False
sweep_dir = 1
running = True

# Values from FPGA
servo_x = servo_y = pred_x = pred_y = None

while running:
    screen.fill((20, 20, 20))

    # Grid and axes
    for i in range(GRID_DIV + 1):
        pygame.draw.line(screen, (50, 50, 50), (i * WIDTH // GRID_DIV, 0), (i * WIDTH // GRID_DIV, HEIGHT))
        pygame.draw.line(screen, (50, 50, 50), (0, i * HEIGHT // GRID_DIV), (WIDTH, i * HEIGHT // GRID_DIV))
    pygame.draw.line(screen, (150, 150, 150), (CENTER_X, 0), (CENTER_X, HEIGHT), 2)
    pygame.draw.line(screen, (150, 150, 150), (0, CENTER_Y), (WIDTH, CENTER_Y), 2)

    # Keyboard controls
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False
        elif event.type == pygame.KEYDOWN and event.key == pygame.K_a:
            auto_sweep = not auto_sweep

    keys = pygame.key.get_pressed()
    if keys[pygame.K_LEFT]:  x = max(0, x - speed)
    if keys[pygame.K_RIGHT]: x = min(WIDTH - 1, x + speed)
    if keys[pygame.K_UP]:    y = max(0, y - speed)
    if keys[pygame.K_DOWN]:  y = min(HEIGHT - 1, y + speed)
    if keys[pygame.K_SPACE]: x, y = CENTER_X, CENTER_Y

    if auto_sweep:
        x += sweep_dir
        if x >= WIDTH or x <= 0:
            sweep_dir *= -1

    # Calculate logic from object manually (your green dot)
    logic_x = x - CENTER_X
    logic_y = CENTER_Y - y

    # Send position to FPGA
    send_servo_x = SERVO_CENTER + int(logic_x * 90 / (WIDTH // 2))
    send_servo_y = SERVO_CENTER + int(logic_y * 90 / (HEIGHT // 2))
    send_servo_x = max(0, min(180, send_servo_x))
    send_servo_y = max(0, min(180, send_servo_y))

    if ser and ser.is_open:
        try:
            ser.write(bytes([send_servo_y, send_servo_x]))
        except:
            pass

    # Receive prediction + servo feedback
    if ser and ser.in_waiting >= 4:
        try:
            pred_y  = int.from_bytes(ser.read(), "big")
            pred_x  = int.from_bytes(ser.read(), "big")
            servo_y = int.from_bytes(ser.read(), "big")
            servo_x = int.from_bytes(ser.read(), "big")

            if (servo_x, servo_y) == (0, 0): servo_x = servo_y = None
            if (pred_x, pred_y) == (0, 0): pred_x = pred_y = None
        except:
            servo_x = servo_y = pred_x = pred_y = None

    # Draw green current position
    pygame.draw.circle(screen, (0, 255, 0), (x, y), 10)

    # Draw prediction (Red)
    if pred_x is not None and pred_y is not None:
        pred_draw_x = int(CENTER_X + (pred_x - 90) * (WIDTH / 2 / 90))
        pred_draw_y = int(CENTER_Y - (pred_y - 90) * (HEIGHT / 2 / 90))
        pygame.draw.circle(screen, (255, 0, 0), (pred_draw_x, pred_draw_y), 10)

    # Draw servo received (Blue)
    logic_servo_x = logic_servo_y = None
    if servo_x is not None and servo_y is not None:
        logic_servo_x = (servo_x - 90) * (WIDTH / 2 / 90)
        logic_servo_y = (servo_y - 90) * (HEIGHT / 2 / 90)
        draw_servo_x = int(CENTER_X + logic_servo_x)
        draw_servo_y = int(CENTER_Y - logic_servo_y)
        pygame.draw.circle(screen, (0, 0, 255), (draw_servo_x, draw_servo_y), 10)

    # Text Display
    text = f"Green Obj XY: ({logic_x}, {logic_y})"
    if servo_x is not None:
        text += f" | Blue ServoXY: ({servo_x},{servo_y}) → ({int(logic_servo_x)}, {int(logic_servo_y)})"
    if pred_x is not None:
        text += f" | Red PredXY: ({pred_x},{pred_y})"
    screen.blit(font.render(text, True, (255, 255, 255)), (10, 10))

    pygame.display.flip()
    clock.tick(30)

if ser:
    ser.close()
pygame.quit()
