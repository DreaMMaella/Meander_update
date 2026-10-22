import 'dart:math';
import 'dart:ui';

import 'package:canvas_app/plugin_host/canvas/display_object.dart';

class CollisionPair {
  final String objectIdA;
  final String objectIdB;

  const CollisionPair(this.objectIdA, this.objectIdB);

  @override
  bool operator ==(Object other) =>
      other is CollisionPair &&
      ((objectIdA == other.objectIdA && objectIdB == other.objectIdB) ||
          (objectIdA == other.objectIdB && objectIdB == other.objectIdA));

  @override
  int get hashCode => objectIdA.hashCode ^ objectIdB.hashCode;
}

class PhysicsBody {
  final String objectId;
  double vx = 0;
  double vy = 0;
  double gravityScale = 1;
  double friction = 0;
  double restitution = 0.5;
  bool isStatic = false;
  bool isActive = true;

  PhysicsBody({required this.objectId});
}

class PhysicsEngine {
  final Map<String, PhysicsBody> _bodies = {};
  final Set<CollisionPair> _activeCollisions = {};
  final List<Function(String, String)> _collisionListeners = [];
  double _gravityX = 0;
  double _gravityY = 980;

  double get gravityX => _gravityX;
  double get gravityY => _gravityY;

  void setGravity(double x, double y) {
    _gravityX = x;
    _gravityY = y;
  }

  void addBody(PhysicsBody body) {
    _bodies[body.objectId] = body;
  }

  void removeBody(String objectId) {
    _bodies.remove(objectId);
  }

  void onCollision(Function(String, String) callback) {
    _collisionListeners.add(callback);
  }

  void update(Duration delta, DisplayScene scene) {
    final dt = delta.inMilliseconds / 1000.0;

    for (final body in _bodies.values) {
      if (body.isStatic || !body.isActive) continue;

      final obj = scene.objectMap[body.objectId];
      if (obj == null) continue;

      body.vy += _gravityY * body.gravityScale * dt;
      body.vx += _gravityX * body.gravityScale * dt;

      if (body.friction > 0) {
        body.vx *= (1 - body.friction * dt);
        body.vy *= (1 - body.friction * dt);
      }

      obj.x += body.vx * dt;
      obj.y += body.vy * dt;
    }

    _checkCollisions(scene);
  }

  void _checkCollisions(DisplayScene scene) {
    final newCollisions = <CollisionPair>{};

    final activeObjects = _bodies.values
        .where((b) => b.isActive)
        .map((b) => scene.objectMap[b.objectId])
        .where((o) => o != null)
        .toList();

    for (int i = 0; i < activeObjects.length; i++) {
      for (int j = i + 1; j < activeObjects.length; j++) {
        final a = activeObjects[i]!;
        final b = activeObjects[j]!;

        if (_intersects(a, b)) {
          final pair = CollisionPair(a.id, b.id);
          newCollisions.add(pair);

          if (!_activeCollisions.contains(pair)) {
            _onCollision(a.id, b.id);
          }

          _resolveCollision(a, b);
        }
      }
    }

    _activeCollisions.clear();
    _activeCollisions.addAll(newCollisions);
  }

  bool _intersects(DisplayObject a, DisplayObject b) {
    if (a.type == DisplayObjectType.circle && b.type == DisplayObjectType.circle) {
      return _circleCircle(a, b);
    }
    if (a.type == DisplayObjectType.rect && b.type == DisplayObjectType.rect) {
      return _rectRect(a, b);
    }
    return _circleRect(
      a.type == DisplayObjectType.circle ? a : b,
      a.type == DisplayObjectType.rect ? a : b,
    );
  }

  bool _circleCircle(DisplayObject a, DisplayObject b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final distSq = dx * dx + dy * dy;
    final radiiSum = a.radius + b.radius;
    return distSq <= radiiSum * radiiSum;
  }

  bool _rectRect(DisplayObject a, DisplayObject b) {
    return (a.x - a.width / 2 < b.x + b.width / 2) &&
        (a.x + a.width / 2 > b.x - b.width / 2) &&
        (a.y - a.height / 2 < b.y + b.height / 2) &&
        (a.y + a.height / 2 > b.y - b.height / 2);
  }

  bool _circleRect(DisplayObject circle, DisplayObject rect) {
    final closestX = max(rect.x - rect.width / 2,
        min(circle.x, rect.x + rect.width / 2));
    final closestY = max(rect.y - rect.height / 2,
        min(circle.y, rect.y + rect.height / 2));
    final dx = circle.x - closestX;
    final dy = circle.y - closestY;
    return (dx * dx + dy * dy) < (circle.radius * circle.radius);
  }

  void _resolveCollision(DisplayObject a, DisplayObject b) {
    final bodyA = _bodies[a.id];
    final bodyB = _bodies[b.id];
    if (bodyA == null || bodyB == null) return;
    if (bodyA.isStatic && bodyB.isStatic) return;

    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist == 0) return;

    final nx = dx / dist;
    final ny = dy / dist;

    final overlap = _calculateOverlap(a, b);
    if (overlap <= 0) return;

    if (!bodyA.isStatic && !bodyB.isStatic) {
      a.x -= nx * overlap / 2;
      a.y -= ny * overlap / 2;
      b.x += nx * overlap / 2;
      b.y += ny * overlap / 2;

      final relVx = bodyB.vx - bodyA.vx;
      final relVy = bodyB.vy - bodyA.vy;
      final relVn = relVx * nx + relVy * ny;

      if (relVn > 0) return;

      final restitution = max(bodyA.restitution, bodyB.restitution);
      final impulse = -(1 + restitution) * relVn / 2;

      bodyA.vx -= impulse * nx;
      bodyA.vy -= impulse * ny;
      bodyB.vx += impulse * nx;
      bodyB.vy += impulse * ny;
    } else if (bodyA.isStatic) {
      b.x += nx * overlap;
      b.y += ny * overlap;
      final vn = bodyB.vx * nx + bodyB.vy * ny;
      if (vn < 0) {
        bodyB.vx -= (1 + bodyB.restitution) * vn * nx;
        bodyB.vy -= (1 + bodyB.restitution) * vn * ny;
      }
    } else {
      a.x -= nx * overlap;
      a.y -= ny * overlap;
      final vn = bodyA.vx * nx + bodyA.vy * ny;
      if (vn > 0) {
        bodyA.vx -= (1 + bodyA.restitution) * vn * nx;
        bodyA.vy -= (1 + bodyA.restitution) * vn * ny;
      }
    }
  }

  double _calculateOverlap(DisplayObject a, DisplayObject b) {
    if (a.type == DisplayObjectType.circle && b.type == DisplayObjectType.circle) {
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final dist = sqrt(dx * dx + dy * dy);
      return (a.radius + b.radius) - dist;
    }
    if (a.type == DisplayObjectType.rect && b.type == DisplayObjectType.rect) {
      final overlapX = (a.width / 2 + b.width / 2) - (b.x - a.x).abs();
      final overlapY = (a.height / 2 + b.height / 2) - (b.y - a.y).abs();
      return min(overlapX, overlapY);
    }
    return 0;
  }

  void _onCollision(String idA, String idB) {
    for (final listener in _collisionListeners) {
      listener(idA, idB);
    }
  }

  void applyForce(String objectId, double fx, double fy) {
    final body = _bodies[objectId];
    if (body == null || body.isStatic) return;
    body.vx += fx;
    body.vy += fy;
  }

  void applyImpulse(String objectId, double ix, double iy) {
    final body = _bodies[objectId];
    if (body == null || body.isStatic) return;
    body.vx += ix;
    body.vy += iy;
  }

  void setVelocity(String objectId, double vx, double vy) {
    final body = _bodies[objectId];
    if (body == null) return;
    body.vx = vx;
    body.vy = vy;
  }
}
